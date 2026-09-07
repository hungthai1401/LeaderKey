import Cocoa
import Defaults

/// The key that Caps Lock is repointed at.
///
/// A HID usage and a Carbon virtual keycode are unrelated numbers, and the
/// virtual keycodes for these keys are not even in order (F15 is 0x71 while
/// F16 is 0x6A), so both sides are written out rather than derived.
///
/// F18 is the default because no Mac keyboard ships the key, so nothing else
/// can be listening for it. The rest are here for anyone who already has a
/// function key bound by another app.
enum TriggerKey: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
  case f13, f14, f15, f16, f17, f18, f19

  var id: Self { self }

  /// Keyboard/Keypad page usage, packed the way the HID event system wants it:
  /// page 0x07 in the high 32 bits, usage in the low 32.
  var hidUsage: UInt64 {
    switch self {
    case .f13: return 0x7_0000_0068
    case .f14: return 0x7_0000_0069
    case .f15: return 0x7_0000_006A
    case .f16: return 0x7_0000_006B
    case .f17: return 0x7_0000_006C
    case .f18: return 0x7_0000_006D
    case .f19: return 0x7_0000_006E
    }
  }

  /// What a CGEvent reports once the remap is in place.
  var virtualKeyCode: CGKeyCode {
    switch self {
    case .f13: return 0x69
    case .f14: return 0x6B
    case .f15: return 0x71
    case .f16: return 0x6A
    case .f17: return 0x40
    case .f18: return 0x4F
    case .f19: return 0x50
    }
  }

  var description: String { rawValue.uppercased() }
}

/// What a quick tap of Caps Lock does, when it was pressed and released
/// without another key joining in.
enum TapBehavior: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
  /// Open the Leader Key panel. One key instead of a chord.
  case leaderKey
  /// The Vim reflex.
  case escape
  /// Toggle the real Caps Lock, LED and all.
  case capsLock
  case nothing

  var id: Self { self }

  var description: String {
    switch self {
    case .leaderKey: return "Open Leader Key"
    case .escape: return "Escape"
    case .capsLock: return "Toggle Caps Lock"
    case .nothing: return "Nothing"
    }
  }
}

/// What holding Caps Lock on its own does, once it is held past the threshold
/// without another key.
///
/// Holding Caps Lock *with* another key is always Hyper, in both modes. The
/// two only differ on what a lone hold means.
enum HoldBehavior: String, Codable, CaseIterable, Identifiable, Defaults.Serializable {
  /// Nothing extra. Caps Lock is a plain Hyper modifier, same as Hyperkey.
  case hyperOnly
  /// Open the Leader Key panel and keep it open while the key is down, so a
  /// sequence can be typed and the panel dismissed by letting go.
  case peekLeaderKey

  var id: Self { self }

  var description: String {
    switch self {
    case .hyperOnly: return "Hyper only (⌃⌥⇧⌘)"
    case .peekLeaderKey: return "Peek Leader Key while held"
    }
  }
}
