import Cocoa

/// The tap / chord / hold decision for the trigger key.
///
/// No CGEvent, no clock of its own and no side effects: it takes an input and
/// says what should happen. That is deliberate. The event tap this normally
/// sits behind needs a keyboard, a logged-in GUI session and the Accessibility
/// permission, so anything welded to the tap cannot be tested. This can.
///
/// The gesture the tap cannot resolve at key-down time is which of three
/// things a press will turn out to be. Rather than buffer events until the
/// answer arrives, the trigger key is swallowed outright and never reaches an
/// app, so there is nothing to replay and no rollover to untangle. The answer
/// then falls out of whatever happens next:
///
/// - another key arrives first, and it is a Hyper chord
/// - the hold threshold passes first, and it is a lone hold
/// - the key comes back up first, and it was a tap
struct TriggerGesture {
  struct Config: Equatable {
    var tapBehavior: TapBehavior = .leaderKey
    var holdBehavior: HoldBehavior = .hyperOnly
    /// A release later than this is not a tap, even with nothing else pressed.
    var tapTimeout: TimeInterval = 0.25
    /// How long a lone hold lasts before the peek panel opens.
    var holdThreshold: TimeInterval = 0.15
    /// Whether releasing the key closes a peek panel that is still open.
    var closePeekOnRelease: Bool = true
  }

  enum Phase: Equatable {
    /// Trigger key is up.
    case idle
    /// Trigger key is down and the gesture is undecided.
    case armed
    /// Another key came first. Flags get merged until release.
    case hyper
    /// Held past the threshold. The panel is open and owns the keyboard.
    case peek
  }

  /// What the caller should do with the event it just handed over.
  enum Disposition: Equatable {
    case pass
    case passWithHyper
  }

  /// Work for the caller to carry out. Returned as data rather than performed
  /// here, so a test can assert on the decision instead of watching for a
  /// side effect.
  enum Effect: Equatable {
    case startHoldTimer(after: TimeInterval)
    case cancelHoldTimer
    case openPanel
    case dismissPanel
    case tap(TapBehavior)
  }

  var config: Config
  private(set) var phase: Phase = .idle
  private var pressedAt: TimeInterval = 0

  /// Keys whose key-down went out carrying Hyper. Their key-up has to carry
  /// the same flags even after the chord has ended, which is what happens
  /// every time Caps Lock is released before the key it was chorded with.
  private var flaggedKeys: Set<CGKeyCode> = []

  init(config: Config = Config()) {
    self.config = config
  }

  /// The trigger key is always swallowed, so these return effects only.
  @discardableResult
  mutating func triggerDown(at now: TimeInterval) -> [Effect] {
    // A function key repeats while held. Only the first press opens a
    // gesture; the repeats fall through to the same swallow.
    guard phase == .idle else { return [] }

    pressedAt = now
    phase = .armed

    guard config.holdBehavior == .peekLeaderKey else { return [] }
    return [.startHoldTimer(after: config.holdThreshold)]
  }

  @discardableResult
  mutating func triggerUp(at now: TimeInterval) -> [Effect] {
    let previous = phase
    let heldFor = now - pressedAt
    phase = .idle
    pressedAt = 0
    // `flaggedKeys` deliberately survives: those keys may still be physically
    // down, and their key-up still needs the flags.

    var effects: [Effect] = [.cancelHoldTimer]

    switch previous {
    case .armed:
      // Nothing claimed the press. A slow release is a hold that did
      // nothing, not a tap, so it stays silent.
      if heldFor < config.tapTimeout {
        effects.append(.tap(config.tapBehavior))
      }
    case .peek:
      if config.closePeekOnRelease {
        effects.append(.dismissPanel)
      }
    case .hyper, .idle:
      break
    }

    return effects
  }

  @discardableResult
  mutating func holdThresholdReached() -> [Effect] {
    // Checked here rather than trusting the caller not to arm a timer in
    // hyper-only mode. `update(config:)` can switch modes while a timer is
    // already in flight: it cancels the timer, but a handler that has already
    // started and is blocked on the caller's lock still runs afterwards, and
    // would otherwise open the panel in a mode that has no panel.
    guard config.holdBehavior == .peekLeaderKey else { return [] }

    // A key or a release may have landed between the timer firing and this
    // call, in which case the press is already claimed.
    guard phase == .armed else { return [] }

    phase = .peek
    return [.openPanel]
  }

  @discardableResult
  mutating func otherKeyDown(_ code: CGKeyCode) -> (Disposition, [Effect]) {
    switch phase {
    case .armed:
      // A key beat the hold timer, so this is a Hyper chord.
      phase = .hyper
      flaggedKeys.insert(code)
      return (.passWithHyper, [.cancelHoldTimer])

    case .hyper:
      flaggedKeys.insert(code)
      return (.passWithHyper, [])

    case .peek:
      // The panel is key window now and reads keys through AppKit, so this
      // one goes through untouched.
      return (.pass, [])

    case .idle:
      return (.pass, [])
    }
  }

  @discardableResult
  mutating func otherKeyUp(_ code: CGKeyCode) -> Disposition {
    // Matched against its own key-down rather than the current phase,
    // because Caps Lock is often released first.
    flaggedKeys.remove(code) != nil ? .passWithHyper : .pass
  }

  /// Drops a half-finished gesture. Needed whenever a key-up may have been
  /// eaten: after wake, after the system disables the tap, or on a settings
  /// change that would otherwise reinterpret a press already in flight.
  mutating func reset() {
    phase = .idle
    pressedAt = 0
    flaggedKeys.removeAll()
  }
}
