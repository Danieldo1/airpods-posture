import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AirPostureCore
#endif

struct MenuBarView: View {
    @EnvironmentObject private var tracker: PostureTrackingManager
    @EnvironmentObject private var settings: AirPostureSettings
    @EnvironmentObject private var weekStore: WeeklyAnalyticsStore
    @EnvironmentObject private var breakClock: BreakReminderClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var optionsExpanded = false
    @State private var summaryExpanded = false

    @State private var visibleScreenHeight: CGFloat = 760

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .padding(.horizontal, 16)

            ScrollView(.vertical, showsIndicators: false) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ConsoleScrollBehavior())
            }
            .clipped()

            Divider()
                .padding(.horizontal, 16)
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 360, height: min(620, visibleScreenHeight))
        .clipped()
        .background(ConsoleScreenReader { visibleScreenHeight = max(200, $0 - 48) })
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if breakClock.isEnabled {
                breakCountdown
            }
            PostureGaugeView(
                readings: tracker.liveReadings,
                showTurnValue: settings.lookAwayGateEnabled || settings.showHeadTurnEnabled,
                showHeadTurn: settings.showHeadTurnEnabled
            )
            PostureAnalyticsView(
                store: weekStore,
                isExpanded: $summaryExpanded
            )
            calibrateButton
            options
            if tracker.authorizationDenied {
                permissionNotice
            } else if let message = tracker.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let storeError = weekStore.lastStoreError {
                Text(storeError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var breakCountdown: some View {
        HStack(spacing: 8) {
            Image(systemName: breakSymbol)
            Text(breakClock.popoverText)
                .font(.body.monospacedDigit())
            Text("to break")
                .foregroundStyle(.secondary)
            Spacer()
            Text(settings.breakKind.title)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Break reminder, \(breakClock.accessibilityRemaining) remaining, \(settings.breakKind.title)")
    }

    private var breakSymbol: String {
        switch settings.breakKind {
        case .walk: "figure.walk"
        case .water: "drop"
        case .eyes: "eye"
        case .mix: "clock"
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("AirPosture")
                .font(.headline)
            Spacer(minLength: 8)
            Picker("Preset", selection: $tracker.activePreset) {
                ForEach(PosturePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 128)
            .accessibilityLabel("Posture preset")
            .accessibilityHint("Desk and Sofa keep separate upright baselines.")
            ConnectionBadge(status: tracker.connectionStatus)
        }
        .accessibilityElement(children: .contain)
    }

    private var calibrateButton: some View {
        Button(action: handleCalibrate) {
            Label(
                tracker.didJustCalibrate ? "Neutral Posture Saved" : "Set Neutral Posture",
                systemImage: tracker.didJustCalibrate ? "checkmark.circle.fill" : "scope"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!tracker.canCalibrate)
        .keyboardShortcut("k", modifiers: [.command])
        .help(
            "Sit upright, then capture your current tilt, lean, and this session’s heading as the baseline."
        )
        .accessibilityHint(
            "Saves your current pitch and roll as upright posture for the selected Desk or Sofa preset, and zeros this session’s heading."
        )
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureHeader(
                title: "Options",
                subtitle: "Monitoring, reminders & appearance",
                systemImage: "slider.horizontal.3",
                isExpanded: optionsExpanded
            ) {
                withAnimation(disclosureAnimation) {
                    optionsExpanded.toggle()
                }
            }

            if optionsExpanded {
                Group {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsGroup("Monitoring", systemImage: "waveform.path.ecg") {
                            VStack(alignment: .leading, spacing: 12) {
                                settingsToggle(
                                    "Tracking",
                                    isOn: $tracker.isTrackingEnabled,
                                    help: "Starts or pauses AirPods posture tracking."
                                )

                                sliderRow(
                                    title: "Sensitivity",
                                    valueText: "\(Int(tracker.sensitivityDegrees))°",
                                    value: $tracker.sensitivityDegrees,
                                    range: 5...30,
                                    step: 1,
                                    accessibilityValue: "\(Int(tracker.sensitivityDegrees)) degrees",
                                    minLabel: "5°",
                                    maxLabel: "30°",
                                    help:
                                        "How far tilt or lean can drift from neutral before it counts as slouching. Lean is treated as more sensitive than tilt."
                                )

                                sliderRow(
                                    title: "Grace Period",
                                    valueText: "\(Int(tracker.gracePeriodSeconds))s",
                                    value: $tracker.gracePeriodSeconds,
                                    range: 1...15,
                                    step: 1,
                                    accessibilityValue: "\(Int(tracker.gracePeriodSeconds)) seconds",
                                    minLabel: "1s",
                                    maxLabel: "15s",
                                    help: "How long you can slouch before AirPosture nudges you."
                                )

                                settingsToggle(
                                    "Ignore slouch when I turn",
                                    isOn: $settings.lookAwayGateEnabled,
                                    help: "Pause tilt and lean scoring while you look aside (second display, talking)."
                                )

                                sliderRow(
                                    title: "Turn-away angle",
                                    valueText: "\(Int(settings.lookAwayThresholdDegrees))°",
                                    value: $settings.lookAwayThresholdDegrees,
                                    range: 20...60,
                                    step: 1,
                                    accessibilityValue: "\(Int(settings.lookAwayThresholdDegrees)) degrees",
                                    minLabel: "20°",
                                    maxLabel: "60°",
                                    help: "How far you can turn before AirPosture treats you as looking aside."
                                )
                                .disabled(!settings.lookAwayGateEnabled)
                                .opacity(settings.lookAwayGateEnabled ? 1 : 0.45)

                                settingsToggle(
                                    "Show head turn",
                                    isOn: $settings.showHeadTurnEnabled,
                                    help: "Rotate the bust left and right with your heading. Does not change scoring."
                                )

                            }
                        }

                        settingsGroup("Breaks", systemImage: "cup.and.saucer") {
                            VStack(alignment: .leading, spacing: 12) {
                                settingsToggle(
                                    "Break reminders",
                                    isOn: $settings.breakRemindersEnabled,
                                    help: "Repeating banner and sound to stand up, drink water, or rest your eyes. Off by default."
                                )
                                sliderRow(
                                    title: "Interval",
                                    valueText: "\(Int(settings.breakIntervalMinutes))m",
                                    value: $settings.breakIntervalMinutes,
                                    range: 5...120,
                                    step: 5,
                                    accessibilityValue: "\(Int(settings.breakIntervalMinutes)) minutes",
                                    minLabel: "5m",
                                    maxLabel: "120m",
                                    help: "How long between break reminders."
                                )
                                .disabled(!settings.breakRemindersEnabled)
                                .opacity(settings.breakRemindersEnabled ? 1 : 0.45)
                                labeledPicker("Break type", selection: $settings.breakKind) {
                                    ForEach(BreakKind.allCases) { kind in
                                        Text(kind.title).tag(kind)
                                    }
                                }
                                .disabled(!settings.breakRemindersEnabled)
                                .opacity(settings.breakRemindersEnabled ? 1 : 0.45)
                            }
                        }

                        settingsGroup("Reminders", systemImage: "bell.badge") {
                            ReminderOptionsView(settings: settings)
                        }

                        settingsGroup("Appearance", systemImage: "paintbrush") {
                            VStack(alignment: .leading, spacing: 12) {
                                labeledPicker("Icon style", selection: $settings.iconFamily) {
                                    ForEach(IconFamily.allCases) { family in
                                        Text(family.title).tag(family)
                                    }
                                }
                                .accessibilityHint(
                                    "Changes the menu-bar symbol. Colors still follow upright, warning, and slouch.")



                            }
                        }

                        settingsGroup("Pause & feedback", systemImage: "moon.zzz") {
                            VStack(alignment: .leading, spacing: 12) {
                                snoozeRow

                                settingsToggle(
                                    "Sit-up chime",
                                    isOn: $settings.sitUpChimeEnabled,
                                    help: "One soft tick when you return upright. Off by default."
                                )
                            }
                        }
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclosureAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0)
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Rectangle()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsToggle(
        _ title: String,
        isOn: Binding<Bool>,
        help: String
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .help(help)
            .accessibilityHint(help)
    }

    @ViewBuilder
    private var snoozeRow: some View {
        if settings.isSnoozed, let end = settings.snoozeEndsAt {
            HStack {
                Text("Snoozed until \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Resume", action: handleResumeSnooze)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Snooze")
                    .font(.subheadline)
                HStack(spacing: 8) {
                    Button("15 min", action: handleSnooze15)
                        .accessibilityLabel("Snooze 15 minutes")
                    Button("45 min", action: handleSnooze45)
                        .accessibilityLabel("Snooze 45 minutes")
                    Button("Until tomorrow", action: handleSnoozeUntilTomorrow)
                        .accessibilityLabel("Snooze until tomorrow")
                }
                .controlSize(.regular)
            }
        }
    }

    private var permissionNotice: some View {
        Text(
            "Motion access is off. Enable it in System Settings → Privacy & Security → Motion & Fitness."
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Text("v1.0.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit AirPosture", action: handleQuit)
                .keyboardShortcut("q")
        }
    }

    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        accessibilityValue: String,
        minLabel: String,
        maxLabel: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                Text(minLabel)
                    .frame(width: 34, alignment: .trailing)

                Group {
                    if let step {
                        Slider(value: value, in: range, step: step)
                    } else {
                        Slider(value: value, in: range)
                    }
                }
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(accessibilityValue))
                .help(help)
                .accessibilityHint(help)

                Text(maxLabel)
                    .frame(width: 38, alignment: .leading)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func labeledPicker<Selection: Hashable, Content: View>(
        _ title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 12)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 124, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }

    private func handleCalibrate() {
        tracker.calibrate()
    }

    private func handleSnooze15() {
        settings.snooze(minutes: 15)
    }

    private func handleSnooze45() {
        settings.snooze(minutes: 45)
    }

    private func handleSnoozeUntilTomorrow() {
        settings.snoozeUntilTomorrow()
    }

    private func handleResumeSnooze() {
        settings.clearSnooze()
    }

    private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}

struct DisclosureHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Collapses this section" : "Expands this section")
    }
}

struct SummaryMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectionBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay {
                    if status == .searching {
                        Circle()
                            .stroke(color.opacity(0.35), lineWidth: 6)
                    }
                }
            Text(status.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.55), in: Capsule())
        .accessibilityLabel(Text("Connection status, \(status.title)"))
    }

    private var color: Color {
        switch status {
        case .connected:
            Color.green
        case .searching:
            Color.orange
        case .disconnected:
            Color.secondary
        }
    }
}


/// Observe the hosting window's actual screen, including moves between displays.
private struct ConsoleScreenReader: NSViewRepresentable {
    var onHeightChange: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScreenView { ScreenView(onHeightChange: onHeightChange) }
    func updateNSView(_ view: ScreenView, context: Context) { view.onHeightChange = onHeightChange }

    final class ScreenView: NSView {
        var onHeightChange: (CGFloat) -> Void
        private var tokens: [NSObjectProtocol] = []
        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
            for name in [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification] {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.report() })
            }
            report()
        }
        private func report() {
            let screen = window?.screen ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            guard let height = screen?.visibleFrame.height else { return }
            DispatchQueue.main.async { [weak self] in self?.onHeightChange(height) }
        }
        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
