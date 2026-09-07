import Foundation

// MARK: - Private IOKit HID event system API
//
// IOKit.framework exports these symbols but ships no public header for them,
// so they are bound by name. hidutil(1) drives the same API, and it is how a
// modifier key gets repointed without a kernel extension or a virtual HID
// device.
//
// Return values use Unmanaged because @_silgen_name skips the Clang importer,
// which means none of the usual CoreFoundation ownership annotations apply.
// Every function below named Create or Copy hands back a +1 reference.

@_silgen_name("IOHIDEventSystemClientCreateSimpleClient")
private func _IOHIDEventSystemClientCreateSimpleClient(
  _ allocator: CFAllocator?
) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetProperty")
private func _IOHIDEventSystemClientSetProperty(
  _ client: AnyObject, _ key: CFString, _ value: AnyObject
) -> Bool

@_silgen_name("IOHIDEventSystemClientCopyProperty")
private func _IOHIDEventSystemClientCopyProperty(
  _ client: AnyObject, _ key: CFString
) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func _IOHIDEventSystemClientCopyServices(
  _ client: AnyObject
) -> Unmanaged<NSArray>?

@_silgen_name("IOHIDServiceClientConformsTo")
private func _IOHIDServiceClientConformsTo(
  _ service: AnyObject, _ usagePage: UInt32, _ usage: UInt32
) -> Bool

@_silgen_name("IOHIDServiceClientSetProperty")
private func _IOHIDServiceClientSetProperty(
  _ service: AnyObject, _ key: CFString, _ value: AnyObject
) -> Bool

@_silgen_name("IOHIDServiceClientCopyProperty")
private func _IOHIDServiceClientCopyProperty(
  _ service: AnyObject, _ key: CFString
) -> Unmanaged<AnyObject>?

/// Short-lived access to the HID event system.
///
/// Both properties this app touches (the key mapping and the caps lock state)
/// live in the HID system rather than in the client, so a client is created
/// per call and dropped again. Nothing needs to stay alive in between.
enum HIDEventSystem {
  /// Usage page and usage that mark a HID service as a keyboard.
  static let genericDesktopPage: UInt32 = 0x01
  static let keyboardUsage: UInt32 = 0x06

  /// Runs `body` against a fresh client, or returns nil if one cannot be made.
  static func withClient<T>(_ body: (AnyObject) -> T) -> T? {
    guard
      let client = _IOHIDEventSystemClientCreateSimpleClient(nil)?
        .takeRetainedValue()
    else { return nil }
    return body(client)
  }

  static func setClientProperty(
    _ key: String, to value: AnyObject, on client: AnyObject
  ) -> Bool {
    _IOHIDEventSystemClientSetProperty(client, key as CFString, value)
  }

  static func clientProperty(_ key: String, on client: AnyObject) -> AnyObject? {
    _IOHIDEventSystemClientCopyProperty(client, key as CFString)?
      .takeRetainedValue()
  }

  /// Every HID service that reports itself as a keyboard. Trackpads, mice and
  /// the assorted virtual services on a Mac are filtered out.
  static func keyboardServices(on client: AnyObject) -> [AnyObject] {
    guard
      let all = _IOHIDEventSystemClientCopyServices(client)?
        .takeRetainedValue() as? [AnyObject]
    else { return [] }
    return all.filter {
      _IOHIDServiceClientConformsTo($0, genericDesktopPage, keyboardUsage)
    }
  }

  static func setServiceProperty(
    _ key: String, to value: AnyObject, on service: AnyObject
  ) -> Bool {
    _IOHIDServiceClientSetProperty(service, key as CFString, value)
  }

  static func serviceProperty(_ key: String, on service: AnyObject) -> AnyObject? {
    _IOHIDServiceClientCopyProperty(service, key as CFString)?
      .takeRetainedValue()
  }
}
