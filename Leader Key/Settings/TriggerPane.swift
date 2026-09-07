import Defaults
import Settings
import SwiftUI

struct TriggerPane: View {
  private let contentWidth = 720.0

  @ObservedObject private var trigger = TriggerManager.shared

  @Default(.capsLockTriggerEnabled) var enabled
  @Default(.capsLockTriggerKey) var triggerKey
  @Default(.capsLockTapBehavior) var tapBehavior
  @Default(.capsLockHoldBehavior) var holdBehavior
  @Default(.capsLockTapTimeoutMS) var tapTimeoutMS
  @Default(.capsLockHoldThresholdMS) var holdThresholdMS
  @Default(.capsLockClosePeekOnRelease) var closePeekOnRelease

  var body: some View {
    Settings.Container(contentWidth: contentWidth) {
      Settings.Section(title: "", bottomDivider: true, verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Take over Caps Lock", isOn: $enabled)
          Text(
            "Points Caps Lock at \(triggerKey.description) in the HID layer, "
              + "then reads tap, chord and hold separately. Turning this off "
              + "hands the key straight back."
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          if enabled {
            statusRow
          }
        }
      }

      Settings.Section(title: "Tap", bottomDivider: true, verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("", selection: $tapBehavior) {
            ForEach(TapBehavior.allCases) { Text($0.description).tag($0) }
          }
          .labelsHidden()
          .frame(width: 260)

          Stepper(
            "Counts as a tap under \(tapTimeoutMS) ms",
            value: $tapTimeoutMS, in: 100...600, step: 25)
          Text("Press and release with no other key. A slower release does nothing.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .disabled(!enabled)
      }

      Settings.Section(title: "Hold", bottomDivider: true, verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("", selection: $holdBehavior) {
            ForEach(HoldBehavior.allCases) { Text($0.description).tag($0) }
          }
          .labelsHidden()
          .frame(width: 260)

          Text("Holding Caps Lock together with another key is always Hyper.")
            .font(.callout)
            .foregroundStyle(.secondary)

          if holdBehavior == .peekLeaderKey {
            Divider().padding(.vertical, 2)
            Stepper(
              "Panel opens after \(holdThresholdMS) ms",
              value: $holdThresholdMS, in: 80...500, step: 10)
            Toggle("Letting go closes the panel", isOn: $closePeekOnRelease)
            Text(
              "Hold to peek, type the sequence, let go. Keep this on for a "
                + "radial-menu feel; turn it off to leave the panel up."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }
        }
        .disabled(!enabled)
      }

      Settings.Section(title: "Trigger key", bottomDivider: false, verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("", selection: $triggerKey) {
            ForEach(TriggerKey.allCases) { Text($0.description).tag($0) }
          }
          .labelsHidden()
          .frame(width: 120)

          Text(
            "The key Caps Lock reports as. F18 is the default because no Mac "
              + "keyboard ships one, so nothing else is listening. Change it "
              + "only if another app already claims F18."
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          Text("HID mapping now: \(trigger.mappingDescription)")
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .textSelection(.enabled)
        }
        .disabled(!enabled)
      }
    }
  }

  @ViewBuilder private var statusRow: some View {
    switch trigger.status {
    case .running:
      Label("Running", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.callout)

    case .off:
      Label("Not running", systemImage: "circle.dashed")
        .foregroundStyle(.secondary)
        .font(.callout)

    case .needsAccessibility:
      VStack(alignment: .leading, spacing: 6) {
        Label(
          "Leader Key needs Accessibility to read the keyboard",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .font(.callout)

        HStack {
          Button("Ask for permission") {
            TriggerManager.shared.requestAccessibility()
          }
          Button("Open System Settings") {
            TriggerManager.shared.openAccessibilitySettings()
          }
          Button("Try again") {
            TriggerManager.shared.restart()
          }
        }
        Text(
          "macOS shows its own prompt only once per app version. After "
            + "granting it, quit and reopen Leader Key."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }

    case .remapFailed:
      VStack(alignment: .leading, spacing: 6) {
        Label(
          "The keyboard accepted the tap but refused the remap",
          systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .font(.callout)
        Text(
          "Another remapper is usually holding Caps Lock. Quit Hyperkey or "
            + "Karabiner-Elements and try again."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        Button("Try again") { TriggerManager.shared.restart() }
      }
    }
  }
}

#Preview {
  TriggerPane()
}
