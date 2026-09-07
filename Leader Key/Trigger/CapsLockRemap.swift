import Cocoa
import IOKit
import OSLog

/// Repoints the physical Caps Lock key at a function key.
///
/// This is the layer everything else depends on. macOS debounces the real
/// Caps Lock inside the HID layer by roughly 80ms and never sends key repeats
/// for it, which makes tap-versus-hold timing unusable. Once the key reports
/// as a plain function key that behaviour is gone and every timing decision
/// downstream runs on clean key events.
///
/// The mapping is a HID system property, so it outlives this process and has
/// to be handed back on quit. It does not survive a reboot.
final class CapsLockRemap {
  static let shared = CapsLockRemap()

  private static let mappingProperty = "UserKeyMapping"
  private static let sourceField = "HIDKeyboardModifierMappingSrc"
  private static let destinationField = "HIDKeyboardModifierMappingDst"

  /// Caps Lock on the Keyboard/Keypad page.
  private static let capsLockUsage: UInt64 = 0x7_0000_0039

  /// The key Caps Lock currently points at, or nil when the system owns it.
  private(set) var target: TriggerKey?

  private var watcher: KeyboardArrivalWatcher?

  private init() {}

  @discardableResult
  func apply(target: TriggerKey) -> Bool {
    guard write(mapping(to: target)) else { return false }
    self.target = target
    startWatchingForKeyboards()
    return true
  }

  /// Hands Caps Lock back to the system. Skipping this on quit leaves the key
  /// dead until the user reboots, so it runs from applicationWillTerminate.
  @discardableResult
  func revert() -> Bool {
    watcher?.stop()
    watcher = nil
    // The mapping property is shared with every other remapper on the
    // machine. Clearing it when we never set it would wipe out whatever
    // Hyperkey or Karabiner put there, which is exactly what happens on
    // launch with the trigger switched off.
    guard target != nil else { return true }
    guard write([]) else { return false }
    target = nil
    return true
  }

  /// Re-sends the current mapping. Needed after wake on some machines, and
  /// for a keyboard that was plugged in after the mapping was set.
  @discardableResult
  func reapply() -> Bool {
    guard let target else { return false }
    return write(mapping(to: target))
  }

  /// True when the HID system is actually holding the mapping this object
  /// thinks it set. Worth checking before blaming the event tap.
  func isMappingLive() -> Bool {
    guard let target else { return false }
    let expected = target.hidUsage
    return currentMapping().contains { pair in
      (pair[Self.sourceField] as? NSNumber)?.uint64Value == Self.capsLockUsage
        && (pair[Self.destinationField] as? NSNumber)?.uint64Value == expected
    }
  }

  /// Whatever the HID system currently holds, for the diagnostics row in
  /// Settings. Other apps write here too, so this is not necessarily ours.
  func currentMapping() -> [[String: Any]] {
    let value = HIDEventSystem.withClient { client in
      HIDEventSystem.clientProperty(Self.mappingProperty, on: client)
    }
    return (value as? [[String: Any]]) ?? []
  }

  private func mapping(to target: TriggerKey) -> [[String: Any]] {
    [
      [
        Self.sourceField: NSNumber(value: Self.capsLockUsage),
        Self.destinationField: NSNumber(value: target.hidUsage),
      ]
    ]
  }

  /// The property has to go on the event system client rather than on each
  /// keyboard service. Setting HIDKeyboardModifierMappingPairs per service
  /// returns false on macOS 15; the client-level UserKeyMapping is the path
  /// hidutil(1) uses and the one that takes effect.
  private func write(_ pairs: [[String: Any]]) -> Bool {
    let result = HIDEventSystem.withClient { client in
      HIDEventSystem.setClientProperty(
        Self.mappingProperty, to: pairs as NSArray, on: client)
    }
    if result == nil {
      triggerLog.error("no HID event system client")
    } else {
      let accepted = result == true
      triggerLog.notice(
        "wrote \(pairs.count, privacy: .public) pair(s), ok=\(accepted, privacy: .public)")
    }
    return result ?? false
  }

  private func startWatchingForKeyboards() {
    guard watcher == nil else { return }
    let watcher = KeyboardArrivalWatcher { [weak self] in
      self?.reapply()
    }
    watcher.start()
    self.watcher = watcher
  }
}

/// Calls back when a HID device shows up, so a mapping set at launch also
/// covers a keyboard attached later.
///
/// This watches the IOKit registry rather than opening any device for input,
/// which keeps it clear of the Input Monitoring permission.
private final class KeyboardArrivalWatcher {
  private let onArrival: () -> Void
  private var notifyPort: IONotificationPortRef?
  private var iterator: io_iterator_t = 0
  private var pending: DispatchWorkItem?

  init(onArrival: @escaping () -> Void) {
    self.onArrival = onArrival
  }

  func start() {
    guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault)
    else { return }
    notifyPort = port
    IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOServiceMatchingCallback = { refcon, iterator in
      drain(iterator)
      guard let refcon else { return }
      Unmanaged<KeyboardArrivalWatcher>.fromOpaque(refcon)
        .takeUnretainedValue()
        .scheduleReapply()
    }

    // "IOServiceFirstMatch" is kIOFirstMatchNotification, spelled out because
    // these IOKit notification types are string #defines that Swift does not
    // reliably import. First-match rather than publish: it arrives once per
    // device and only after the drivers are loaded, so the HID service exists
    // and can actually take the mapping.
    let matching = IOServiceMatching("IOHIDInterface")
    IOServiceAddMatchingNotification(
      port, "IOServiceFirstMatch", matching, callback, context, &iterator)

    // The devices already attached sit in the iterator and have to be
    // consumed, or the first real notification never fires.
    drain(iterator)
  }

  func stop() {
    pending?.cancel()
    pending = nil
    if iterator != 0 {
      IOObjectRelease(iterator)
      iterator = 0
    }
    if let notifyPort {
      IONotificationPortDestroy(notifyPort)
      self.notifyPort = nil
    }
  }

  /// A single keyboard announces several HID interfaces as it comes up, and
  /// mice and trackpads land here too, so the burst is collapsed into one
  /// re-apply.
  fileprivate func scheduleReapply() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.onArrival() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
  }

  deinit { stop() }
}

private func drain(_ iterator: io_iterator_t) {
  var service = IOIteratorNext(iterator)
  while service != 0 {
    IOObjectRelease(service)
    service = IOIteratorNext(iterator)
  }
}
