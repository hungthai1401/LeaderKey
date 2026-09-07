import Cocoa

/// Reads and flips the real Caps Lock, LED included.
///
/// Posting a synthetic keyCode 0x39 does not work: the key is remapped away,
/// and even without the remap a synthetic press does not move the lock state.
/// Writing HIDCapsLockState on each keyboard service does, and unlike
/// IOHIDSetModifierLockState it needs no extra permission.
enum CapsLockState {
  private static let property = "HIDCapsLockState"

  /// Current state, read straight from the window server's view of the
  /// hardware rather than from a HID service, so it is right even when
  /// another app changed it.
  static var isOn: Bool {
    CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
  }

  @discardableResult
  static func toggle() -> Bool {
    set(!isOn)
  }

  @discardableResult
  static func set(_ on: Bool) -> Bool {
    let result = HIDEventSystem.withClient { client -> Bool in
      let keyboards = HIDEventSystem.keyboardServices(on: client)
      guard !keyboards.isEmpty else { return false }
      // Every attached keyboard shares one lock state, but which service
      // accepts the write depends on the machine, so all of them get it.
      return keyboards.reduce(false) { accepted, service in
        let ok = HIDEventSystem.setServiceProperty(
          property, to: NSNumber(value: on), on: service)
        return accepted || ok
      }
    }
    return result ?? false
  }
}
