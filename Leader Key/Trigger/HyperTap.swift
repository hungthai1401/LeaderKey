import Cocoa
import OSLog

/// Drives a `TriggerGesture` from a CGEventTap.
///
/// This half is deliberately dumb: create the tap, park it on its own thread,
/// translate CGEvents into gesture inputs, and carry out whatever effects come
/// back. Every decision lives in `TriggerGesture`, which is where the tests
/// are, because none of this can run without a keyboard and the Accessibility
/// permission.
final class HyperTap {
  struct Config {
    var triggerKey: TriggerKey = .f18
    var gesture = TriggerGesture.Config()

    static let hyperFlags: CGEventFlags = [
      .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]
  }

  /// Open the Leader Key panel. Called on the main queue.
  var onActivateLeaderKey: (() -> Void)?
  /// Close a panel that a hold opened. Called on the main queue.
  var onDismissLeaderKey: (() -> Void)?
  /// The tap could not be created, which in practice always means the
  /// Accessibility permission is missing. Called on the main queue.
  var onTapRejected: (() -> Void)?

  /// Tags the events this class posts itself, so the callback waves them
  /// through instead of tapping its own tail.
  private static let syntheticMarker: Int64 = 0x1EAD_E312

  /// Guards `gesture` and `triggerKey`, which the tap thread reads on every
  /// keystroke and the main thread rewrites on a settings change.
  private let lock = NSLock()
  private var gesture: TriggerGesture
  private var triggerKey: TriggerKey

  /// Guards the port fields, which are written from the main thread and read
  /// from the tap thread. Separate from `lock` because the re-enable path
  /// takes both and NSLock is not recursive.
  private let portLock = NSLock()
  private var machPort: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var tapRunLoop: CFRunLoop?
  private var tapThread: Thread?

  private let sideQueue = DispatchQueue(
    label: "app.leaderkey.hyper-tap.side", qos: .userInteractive)
  private var holdTimer: DispatchSourceTimer?

  init(config: Config = Config()) {
    gesture = TriggerGesture(config: config.gesture)
    triggerKey = config.triggerKey
  }

  // MARK: - Lifecycle

  var isRunning: Bool {
    portLock.lock()
    defer { portLock.unlock() }
    return machPort != nil
  }

  /// Creates the tap and parks it on its own thread. Returns false when the
  /// Accessibility permission has not been granted.
  @discardableResult
  func start() -> Bool {
    portLock.lock()
    let alreadyUp = machPort != nil
    portLock.unlock()
    guard !alreadyUp else { return true }

    let mask =
      CGEventMask(1 << CGEventType.keyDown.rawValue)
      | CGEventMask(1 << CGEventType.keyUp.rawValue)
      | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    guard
      let port = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, refcon in
          guard let refcon else { return Unmanaged.passUnretained(event) }
          return Unmanaged<HyperTap>.fromOpaque(refcon)
            .takeUnretainedValue()
            .handle(type: type, event: event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      triggerLog.error("CGEvent.tapCreate returned nil")
      DispatchQueue.main.async { self.onTapRejected?() }
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    portLock.lock()
    machPort = port
    runLoopSource = source
    portLock.unlock()

    // The tap gets its own thread so a busy main thread cannot stall the
    // callback and get the tap switched off by the system.
    let ready = DispatchSemaphore(value: 0)
    let thread = Thread { [weak self] in
      Thread.current.name = "app.leaderkey.hyper-tap"
      guard let self else {
        ready.signal()
        return
      }
      self.portLock.lock()
      self.tapRunLoop = CFRunLoopGetCurrent()
      self.portLock.unlock()
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CGEvent.tapEnable(tap: port, enable: true)
      ready.signal()
      CFRunLoopRun()
    }
    thread.qualityOfService = .userInteractive
    thread.start()
    tapThread = thread
    // Wait until the source is on the thread's run loop, so a stop() landing
    // straight after has a run loop to stop.
    ready.wait()

    return true
  }

  func stop() {
    portLock.lock()
    let port = machPort
    let source = runLoopSource
    let loop = tapRunLoop
    machPort = nil
    runLoopSource = nil
    tapRunLoop = nil
    tapThread = nil
    portLock.unlock()

    // Invalidate the port before stopping the run loop, so no callback can
    // fire against fields that are already cleared.
    if let port {
      CGEvent.tapEnable(tap: port, enable: false)
      CFMachPortInvalidate(port)
    }
    if let source {
      CFRunLoopSourceInvalidate(source)
    }
    if let loop {
      CFRunLoopStop(loop)
    }
    reset()
  }

  func update(config: Config) {
    lock.lock()
    triggerKey = config.triggerKey
    gesture.config = config.gesture
    // A threshold that changed mid-press would apply to the press in flight,
    // so the gesture is abandoned rather than half-reinterpreted.
    gesture.reset()
    lock.unlock()
    cancelHoldTimer()
  }

  /// Drops any half-finished gesture. Call this whenever the machine may have
  /// eaten a key-up: after wake, or after the system disables the tap.
  func reset() {
    lock.lock()
    gesture.reset()
    lock.unlock()
    cancelHoldTimer()
  }

  // MARK: - Event handling

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // The system switches the tap off if a callback overruns, and again
      // when the user hits the panic chord. Drop the gesture in flight and
      // turn it back on, or the app silently stops working.
      reset()
      portLock.lock()
      let port = machPort
      portLock.unlock()
      if let port {
        CGEvent.tapEnable(tap: port, enable: true)
      }
      return Unmanaged.passUnretained(event)

    case .keyDown:
      guard !isSynthetic(event) else { return Unmanaged.passUnretained(event) }
      return handleKeyDown(event)

    case .keyUp:
      guard !isSynthetic(event) else { return Unmanaged.passUnretained(event) }
      return handleKeyUp(event)

    default:
      return Unmanaged.passUnretained(event)
    }
  }

  private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let code = keyCode(of: event)
    let now = CFAbsoluteTimeGetCurrent()

    lock.lock()
    if code == triggerKey.virtualKeyCode {
      let effects = gesture.triggerDown(at: now)
      lock.unlock()
      run(effects)
      // The trigger key never reaches an app.
      return nil
    }
    let (disposition, effects) = gesture.otherKeyDown(code)
    lock.unlock()

    run(effects)
    return dispatch(disposition, for: event)
  }

  private func handleKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
    let code = keyCode(of: event)
    let now = CFAbsoluteTimeGetCurrent()

    lock.lock()
    if code == triggerKey.virtualKeyCode {
      let effects = gesture.triggerUp(at: now)
      lock.unlock()
      run(effects)
      return nil
    }
    let disposition = gesture.otherKeyUp(code)
    lock.unlock()

    return dispatch(disposition, for: event)
  }

  private func dispatch(
    _ disposition: TriggerGesture.Disposition, for event: CGEvent
  ) -> Unmanaged<CGEvent> {
    if disposition == .passWithHyper {
      event.flags.formUnion(Config.hyperFlags)
    }
    return Unmanaged.passUnretained(event)
  }

  // MARK: - Effects
  //
  // Called from the tap thread with `lock` released. Everything hops to
  // another queue so the callback returns immediately.

  private func run(_ effects: [TriggerGesture.Effect]) {
    for effect in effects {
      switch effect {
      case .startHoldTimer(let delay):
        startHoldTimer(after: delay)
      case .cancelHoldTimer:
        cancelHoldTimer()
      case .openPanel:
        DispatchQueue.main.async { self.onActivateLeaderKey?() }
      case .dismissPanel:
        DispatchQueue.main.async { self.onDismissLeaderKey?() }
      case .tap(let behavior):
        performTap(behavior)
      }
    }
  }

  private func performTap(_ behavior: TapBehavior) {
    switch behavior {
    case .leaderKey:
      DispatchQueue.main.async { self.onActivateLeaderKey?() }
    case .escape:
      sideQueue.async { Self.postEscape() }
    case .capsLock:
      sideQueue.async { CapsLockState.toggle() }
    case .nothing:
      break
    }
  }

  private func startHoldTimer(after delay: TimeInterval) {
    cancelHoldTimer()
    let timer = DispatchSource.makeTimerSource(queue: sideQueue)
    timer.schedule(deadline: .now() + delay)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      self.lock.lock()
      let effects = self.gesture.holdThresholdReached()
      self.lock.unlock()
      self.run(effects)
    }
    timer.resume()
    holdTimer = timer
  }

  private func cancelHoldTimer() {
    holdTimer?.cancel()
    holdTimer = nil
  }

  private static func postEscape() {
    // A private source keeps the physically held modifiers out of the
    // synthetic press, so this is a bare Escape rather than whatever the user
    // happens to be resting on.
    guard let source = CGEventSource(stateID: .privateState) else { return }
    for isDown in [true, false] {
      guard
        let event = CGEvent(
          keyboardEventSource: source, virtualKey: 0x35, keyDown: isDown)
      else { continue }
      event.flags = []
      event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
      event.post(tap: .cghidEventTap)
    }
  }

  private func isSynthetic(_ event: CGEvent) -> Bool {
    event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
  }

  private func keyCode(of event: CGEvent) -> CGKeyCode {
    CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
  }

  deinit { stop() }
}
