import Defaults
import Settings
import SwiftUI

struct TriggerPane: View {
  private let contentWidth = 720.0

  @ObservedObject private var trigger = TriggerManager.shared

  @Default(.capsLockTriggerEnabled) var enabled
  @Default(.triggerSource) var source
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
          Toggle("Take over \(source.description)", isOn: $enabled)
          Text(
            "Points \(source.description) at \(triggerKey.description) in the "
              + "HID layer, then reads tap, chord and hold separately. "
              + "Turning this off hands the key straight back."
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

          if holdBehavior == .peekLeaderKey && tapTimeoutMS > holdThresholdMS {
            Text(
              "In peek mode the panel opens at \(holdThresholdMS) ms, so a "
                + "release later than that is a peek and never reaches this "
                + "window. Only the first \(holdThresholdMS) ms of it apply."
            )
            .font(.callout)
            .foregroundStyle(.orange)
          }
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

          Text(
            "Holding \(source.description) together with another key is always "
              + "Hyper."
          )
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

      Settings.Section(title: "Keys", bottomDivider: false, verticalAlignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Hand over", selection: $source) {
            ForEach(TriggerSource.allCases) { Text($0.description).tag($0) }
          }
          .frame(width: 300)

          Text(
            "Caps Lock is the safe answer, since nothing else wants it. A "
              + "right-hand modifier stops working as a modifier for as long "
              + "as this is on."
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          Divider().padding(.vertical, 2)

          Picker("Reports as", selection: $triggerKey) {
            ForEach(TriggerKey.allCases) { Text($0.description).tag($0) }
          }
          .frame(width: 220)

          Text(
            "F18 is the default because no Mac keyboard ships one, so nothing "
              + "else is listening. Change it only if another app already "
              + "claims F18."
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
