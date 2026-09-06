import AppKit
import SwiftUI
import ColorSelector
#if SWIFT_PACKAGE
import AirPostureCore
#endif

/// Preferences are persisted by the settings model; Off only disables visual controls.
struct ReminderOptionsView: View {
    @ObservedObject var settings: AirPostureSettings
    @ObservedObject private var alerts = AlertService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Warning style", selection: $settings.warningStyle) {
                ForEach(WarningStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Early visual cue", isOn: $settings.earlyCueEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("A gentle visual cue before your sensitivity boundary. Scoring and sound timing stay the same.")
                valueSlider("Start cue at", value: $settings.cueStartFraction, range: 0.10...1, step: 0.05,
                            text: percent(settings.cueStartFraction), endpoints: ("10%", "100%"))
                    .disabled(!settings.earlyCueEnabled)
                    .help("Percentage of your combined tilt and lean sensitivity boundary.")
                valueSlider("Fade-in", value: $settings.overlayFadeInSeconds, range: 0.5...10, step: 0.5,
                            text: "\(settings.overlayFadeInSeconds.formatted(.number.precision(.fractionLength(1))))s", endpoints: ("0.5s", "10s"))
                    .help("Time to reach 95% of a held visual cue.")
                valueSlider("Max strength", value: $settings.maxOverlayStrength, range: 0.05...1, step: 0.05,
                            text: percent(settings.maxOverlayStrength), endpoints: ("5%", "100%"))
                    .help("Maximum visibility, remembered separately for each warning style.")
                HStack(spacing: 8) {
                    ForEach(OverlayTint.allCases) { tint in
                        Button { settings.overlayTint = tint } label: {
                            HStack(spacing: 4) {
                                Circle().fill(color(presetColor(tint))).frame(width: 10, height: 10)
                                Text(tint.title)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.overlayColor == presetColor(tint) ? .accentColor : nil)
                        .accessibilityLabel("\(tint.title) overlay color")
                        .accessibilityAddTraits(settings.overlayColor == presetColor(tint) ? .isSelected : [])
                    }
                }
                ColorSelector("Custom color", selection: colorBinding)
                    .showsAlpha(false)
                    .controlSize(.large)
                    .accessibilityLabel("Custom overlay color")
                    .help("Choose an opaque custom color. Max strength controls visibility separately.")
                Button("Reset \(settings.warningStyle.title) appearance") { settings.resetOverlayAppearance() }
                    .controlSize(.small)
            }
            .disabled(settings.warningStyle == .off)

            Divider()
            HStack(spacing: 8) {
                Picker("Sound", selection: $settings.soundPack) {
                    ForEach(SoundPack.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                Button { alerts.previewSound(pack: settings.soundPack, volume: settings.soundVolume) } label: {
                    Label("Preview", systemImage: "play.fill")
                }
                .help("Play the selected sound at this volume, even while monitoring is paused.")
            }
            valueSlider("Sound volume", value: $settings.soundVolume, range: 0.10...0.80, step: 0.05,
                        text: percent(settings.soundVolume), endpoints: ("10%", "80%"))
            Toggle("Wait for 2× grace before sound", isOn: $settings.soundAfterDoubleGrace)
                .toggleStyle(.switch).controlSize(.small)
                .help("Delay sound and banner until twice the grace period. The visual cue stays independent.")
            if let error = alerts.lastPlaybackError {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Sound playback error: \(error)")
            }
        }
        .font(.subheadline)
    }

    private var colorBinding: Binding<Color?> {
        Binding(get: { color(settings.overlayColor) }, set: { selected in
            guard let selected, let rgb = NSColor(selected).usingColorSpace(.sRGB) else { return }
            settings.overlayColor = OverlayColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        })
    }

    private func presetColor(_ tint: OverlayTint) -> OverlayColor {
        switch tint { case .warm: .warm; case .cool: .cool; case .alert: .alert }
    }

    private func color(_ value: OverlayColor) -> Color {
        Color(.sRGB, red: value.red, green: value.green, blue: value.blue, opacity: 1)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                             text: String, endpoints: (String, String)) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(text).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 8) {
                Text(endpoints.0).frame(width: 30, alignment: .trailing)
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel(title).accessibilityValue(text)
                Text(endpoints.1).frame(width: 34, alignment: .leading)
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
