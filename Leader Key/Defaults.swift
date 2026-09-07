import Cocoa
import Defaults

var defaultsSuite =
  ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
  ? UserDefaults(suiteName: UUID().uuidString)!
  : .standard

extension Defaults.Keys {
  static let configDir = Key<String>(
    "configDir", default: UserConfig.defaultDirectory(), suite: defaultsSuite)
  static let showMenuBarIcon = Key<Bool>(
    "showInMenubar", default: true, suite: defaultsSuite)
  static let forceEnglishKeyboardLayout = Key<Bool>(
    "forceEnglishKeyboardLayout", default: false, suite: defaultsSuite)
  static let modifierKeyConfiguration = Key<ModifierKeyConfig>(
    "modifierKeyConfiguration", default: .controlGroupOptionSticky, suite: defaultsSuite)
  static let theme = Key<Theme>(
    "theme", default: .mysteryBox, suite: defaultsSuite)

  static let autoOpenCheatsheet = Key<AutoOpenCheatsheetSetting>(
    "autoOpenCheatsheet",
    default: .delay, suite: defaultsSuite)
  static let cheatsheetDelayMS = Key<Int>(
    "cheatsheetDelayMS", default: 2000, suite: defaultsSuite)
  static let expandGroupsInCheatsheet = Key<Bool>(
    "expandGroupsInCheatsheet", default: false, suite: defaultsSuite)
  static let showAppIconsInCheatsheet = Key<Bool>(
    "showAppIconsInCheatsheet", default: true, suite: defaultsSuite)
  static let showDetailsInCheatsheet = Key<Bool>(
    "showDetailsInCheatsheet", default: true, suite: defaultsSuite)
  static let showFaviconsInCheatsheet = Key<Bool>(
    "showFaviconsInCheatsheet", default: true, suite: defaultsSuite)
  static let reactivateBehavior = Key<ReactivateBehavior>(
    "reactivateBehavior", default: .hide, suite: defaultsSuite)
  static let screen = Key<Screen>(
    "screen", default: .primary, suite: defaultsSuite)

  static let groupShortcuts = Key<Set<String>>(
    "groupShortcuts",
    default: Set(), suite: defaultsSuite)

  // MARK: Caps Lock trigger
  //
  // Off by default. Turning it on repoints the user's Caps Lock key and needs
  // the Accessibility permission, neither of which should happen unasked.

  static let capsLockTriggerEnabled = Key<Bool>(
    "capsLockTriggerEnabled", default: false, suite: defaultsSuite)
  // Named for what it is rather than capsLockTriggerSource, to match its
  // siblings. The older keys keep the names they were stored under, since
  // renaming one means migrating everybody's settings for nothing visible.
  static let triggerSource = Key<TriggerSource>(
    "triggerSource", default: .capsLock, suite: defaultsSuite)
  static let capsLockTriggerKey = Key<TriggerKey>(
    "capsLockTriggerKey", default: .f18, suite: defaultsSuite)
  // A tap keeps doing what the key is printed to do, because a key that
  // sometimes toggles Caps Lock and sometimes opens a panel on a press too
  // quick to feel is worse than either. The panel is on the hold, and it
  // stays open after the key comes back up, so a sequence can be typed with
  // both hands free.
  static let capsLockTapBehavior = Key<TapBehavior>(
    "capsLockTapBehavior", default: .capsLock, suite: defaultsSuite)
  static let capsLockHoldBehavior = Key<HoldBehavior>(
    "capsLockHoldBehavior", default: .peekLeaderKey, suite: defaultsSuite)
  // Equal on purpose. The panel opens the moment the tap window shuts, so
  // there is no gap in the middle where a press means nothing.
  static let capsLockTapTimeoutMS = Key<Int>(
    "capsLockTapTimeoutMS", default: 250, suite: defaultsSuite)
  static let capsLockHoldThresholdMS = Key<Int>(
    "capsLockHoldThresholdMS", default: 250, suite: defaultsSuite)
  static let capsLockClosePeekOnRelease = Key<Bool>(
    "capsLockClosePeekOnRelease", default: false, suite: defaultsSuite)
}

enum AutoOpenCheatsheetSetting: String, Defaults.Serializable {
  case never
  case always
  case delay
}

enum ModifierKeyConfig: String, Codable, Defaults.Serializable, CaseIterable, Identifiable {
  case controlGroupOptionSticky
  case optionGroupControlSticky

  var id: Self { self }

  var description: String {
    switch self {
    case .controlGroupOptionSticky:
      return "⌃ Group sequences, ⌥ Sticky mode"
    case .optionGroupControlSticky:
      return "⌥ Group sequences, ⌃ Sticky mode"
    }
  }
}

enum ReactivateBehavior: String, Defaults.Serializable {
  case hide
  case reset
  case nothing
}

enum Screen: String, Defaults.Serializable {
  case primary
  case mouse
  case activeWindow
}
