import ApplicationServices
import Cocoa
import Combine
import Defaults

/// Owns the Caps Lock trigger: the HID remap, the event tap, and the lifetime
/// rules that keep the two from drifting apart.
///
/// Nothing here runs unless the user turns it on in Settings. Taking over
/// Caps Lock behind someone's back would be rude, and it needs the
/// Accessibility permission anyway.
final class TriggerManager: ObservableObject {
  static let shared = TriggerManager()

  /// Set by AppDelegate. Opens or focuses the Leader Key panel.
  var activate: (() -> Void)?
  /// Set by AppDelegate. Closes the panel if it is open.
  var dismiss: (() -> Void)?

  /// Published so the Settings pane can show what actually happened rather
  /// than what was asked for.
  @Published private(set) var status: Status = .off

  enum Status: Equatable {
    case off
    case running
    /// The tap was refused, which means Accessibility has not been granted.
    case needsAccessibility
    /// The tap is up but the HID remap did not take.
    case remapFailed

    var isHealthy: Bool { self == .running || self == .off }
  }

  private let tap = HyperTap()
  private var cancellables = Set<AnyCancellable>()
  private var observing = false

  private init() {}

  // MARK: - Setup

  /// Wires up preference and system observers, then starts if enabled.
  func bootstrap() {
    guard !observing else { return }
    observing = true

    tap.onActivateLeaderKey = { [weak self] in self?.activate?() }
    tap.onDismissLeaderKey = { [weak self] in self?.dismiss?() }
    tap.onTapRejected = { [weak self] in
      self?.status = .needsAccessibility
    }

    Task { @MainActor in
      for await enabled in Defaults.updates(.capsLockTriggerEnabled) {
        enabled ? self.start() : self.stop()
      }
    }

    // Changing the trigger key rewrites the mapping and changing a timeout
    // rewrites the gesture rules, so the whole thing is torn down and rebuilt
    // rather than patched while a press might be in flight. `initial: false`
    // keeps the replayed current value from restarting us on launch.
    let rebuildKeys: [Defaults.Keys] = [
      Defaults.Keys.capsLockTriggerKey,
      Defaults.Keys.capsLockTapBehavior,
      Defaults.Keys.capsLockHoldBehavior,
      Defaults.Keys.capsLockTapTimeoutMS,
      Defaults.Keys.capsLockHoldThresholdMS,
      Defaults.Keys.capsLockClosePeekOnRelease,
    ]
    Task { @MainActor in
      for await _ in Defaults.updates(rebuildKeys, initial: false) {
        guard Defaults[.capsLockTriggerEnabled] else { continue }
        self.restart()
      }
    }

    let workspace = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
      NSWorkspace.screensDidWakeNotification,
    ] {
      workspace.publisher(for: name)
        .sink { [weak self] _ in self?.recover() }
        .store(in: &cancellables)
    }
  }

  // MARK: - Start and stop

  func start() {
    guard Defaults[.capsLockTriggerEnabled] else { return }

    // The tap goes up first. If Accessibility is missing there is no point
    // disabling the user's Caps Lock to prove it.
    guard tap.start() else {
      status = .needsAccessibility
      return
    }
    tap.update(config: currentConfig())

    guard CapsLockRemap.shared.apply(target: Defaults[.capsLockTriggerKey]) else {
      status = .remapFailed
      return
    }
    status = .running
  }

  func stop() {
    tap.stop()
    CapsLockRemap.shared.revert()
    status = .off
  }

  func restart() {
    stop()
    start()
  }

  /// After wake the mapping can be gone and the gesture state can be holding
  /// a key-up that never arrived.
  private func recover() {
    guard status == .running else { return }
    tap.reset()
    if !CapsLockRemap.shared.isMappingLive() {
      CapsLockRemap.shared.reapply()
    }
  }

  // MARK: - Permission

  /// Whether the app can create an event tap at all.
  var hasAccessibility: Bool { AXIsProcessTrusted() }

  /// Opens the system prompt. macOS only shows it once per app version, so
  /// the Settings pane also links straight to the pane in System Settings.
  func requestAccessibility() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
    AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
  }

  func openAccessibilitySettings() {
    guard
      let url = URL(
        string:
          "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  // MARK: - Diagnostics

  /// What the HID system is holding right now, rendered for the Settings
  /// pane. Other apps write to the same property, so this is not necessarily
  /// ours.
  var mappingDescription: String {
    let pairs = CapsLockRemap.shared.currentMapping()
    guard !pairs.isEmpty else { return "none" }
    return pairs.map { pair in
      let src = (pair["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value ?? 0
      let dst = (pair["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value ?? 0
      return String(format: "0x%llX → 0x%llX", src, dst)
    }
    .joined(separator: ", ")
  }

  private func currentConfig() -> HyperTap.Config {
    HyperTap.Config(
      triggerKey: Defaults[.capsLockTriggerKey],
      gesture: TriggerGesture.Config(
        tapBehavior: Defaults[.capsLockTapBehavior],
        holdBehavior: Defaults[.capsLockHoldBehavior],
        tapTimeout: Double(Defaults[.capsLockTapTimeoutMS]) / 1000,
        holdThreshold: Double(Defaults[.capsLockHoldThresholdMS]) / 1000,
        closePeekOnRelease: Defaults[.capsLockClosePeekOnRelease]
      )
    )
  }
}
