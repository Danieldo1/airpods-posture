import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var tracker: PostureTrackingManager
    @EnvironmentObject private var settings: AirPostureSettings
    @EnvironmentObject private var weekStore: WeeklyAnalyticsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var optionsExpanded = false
    @State private var summaryExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            PostureGaugeView(
                pitchDelta: tracker.pitchDeltaDegrees,
                rollDelta: tracker.rollDeltaDegrees,
                yawDelta: tracker.yawDeltaDegrees,
                dominantAxis: tracker.dominantAxis,
                band: tracker.postureBand,
                slouchProgress: tracker.slouchProgressClamped,
                isCalibrated: tracker.isCalibrated && tracker.connectionStatus == .connected,
                caption: tracker.coachingCaption,
                isLookingAway: tracker.isLookingAway,
                showTurnValue: settings.lookAwayGateEnabled || settings.showHeadTurnEnabled,
                showHeadTurn: settings.showHeadTurnEnabled
            )
            WeeklySummarySection(
                summary: weekStore.weekSummary,
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
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
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
                ScrollView {
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

                        settingsGroup("Reminders", systemImage: "bell.badge") {
                            VStack(alignment: .leading, spacing: 12) {
                                labeledPicker("Warning style", selection: $settings.warningStyle) {
                                    ForEach(WarningStyle.allCases) { style in
                                        Text(style.title).tag(style)
                                    }
                                }
                                .help("Edge glow is default. Overlays never block clicks.")
                                .accessibilityHint("Edge glow is default. Overlays never block clicks.")

                                sliderRow(
                                    title: "Max strength",
                                    valueText: "\(Int(settings.maxOverlayStrength * 100))%",
                                    value: $settings.maxOverlayStrength,
                                    range: 0.20...1.00,
                                    accessibilityValue: "\(Int(settings.maxOverlayStrength * 100)) percent",
                                    minLabel: "20%",
                                    maxLabel: "100%",
                                    help: "Ceiling for the overlay. It ramps up after the grace period."
                                )

                                labeledPicker("Sound pack", selection: $settings.soundPack) {
                                    ForEach(SoundPack.allCases) { pack in
                                        Text(pack.title).tag(pack)
                                    }
                                }
                                .accessibilityHint("System sound played with the sit-up reminder.")

                                sliderRow(
                                    title: "Sound volume",
                                    valueText: "\(Int(settings.soundVolume * 100))%",
                                    value: $settings.soundVolume,
                                    range: 0.10...0.80,
                                    accessibilityValue: "\(Int(settings.soundVolume * 100)) percent",
                                    minLabel: "10%",
                                    maxLabel: "80%",
                                    help: "Volume for the warning sound."
                                )

                                settingsToggle(
                                    "Wait for 2× grace before sound",
                                    isOn: $settings.soundAfterDoubleGrace,
                                    help:
                                        "Keep the overlay, but delay sound and banner until you have been slouching for twice the grace period."
                                )

                            }
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

                                labeledPicker("Overlay tint", selection: $settings.overlayTint) {
                                    ForEach(OverlayTint.allCases) { tint in
                                        Text(tint.title).tag(tint)
                                    }
                                }
                                .accessibilityHint(
                                    "Color for screen-edge overlays. Does not recolor the menu-bar icon.")

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
                // A vertical ScrollView has no intrinsic height inside MenuBarExtra.
                // Give the expanded panel a concrete viewport so it cannot collapse to zero.
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .scrollIndicators(.hidden)
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

private struct DisclosureHeader: View {
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

private struct WeeklySummarySection: View {
    let summary: WeekSummary
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureHeader(
                title: "This week",
                subtitle: summary.hasMonitoredTime ? "Your posture at a glance" : "No monitored time yet",
                systemImage: "chart.bar.xaxis",
                isExpanded: isExpanded
            ) {
                withAnimation(disclosureAnimation) {
                    isExpanded.toggle()
                }
            }

            if summary.hasMonitoredTime {
                HStack(spacing: 8) {
                    SummaryMetric(
                        value: summary.percentUpright.map { "\($0)%" } ?? "—",
                        label: "Upright",
                        tint: .green
                    )
                    SummaryMetric(
                        value: "\(summary.slouchEpisodes)",
                        label: summary.slouchEpisodes == 1 ? "Slouch" : "Slouches",
                        tint: .orange
                    )
                    SummaryMetric(
                        value: "\(summary.offNeutralMinutes)m",
                        label: "Off-neutral",
                        tint: .secondary
                    )
                }
            }

            if isExpanded {
                WeekStripView(summary: summary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
    }

    private var disclosureAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0)
    }
}

private struct SummaryMetric: View {
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

private struct WeekStripView: View {
    let summary: WeekSummary

    private let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]
    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily upright")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let delta = summary.vsLastWeekPoints {
                    Text(deltaText(delta))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delta >= 0 ? Color.green : Color.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    WeekBarColumn(
                        letter: weekdayLetters[index],
                        weekdayName: weekdayNames[index],
                        percent: summary.dailyUprightPercents[safe: index] ?? nil,
                        isToday: index == currentWeekdayIndex
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("This week, Monday through Sunday")
        }
    }

    private func deltaText(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta) pts vs last week" }
        if delta < 0 { return "−\(abs(delta)) pts vs last week" }
        return "No change vs last week"
    }

    private var currentWeekdayIndex: Int {
        let calendar = WeeklyAnalyticsMath.isoCalendar()
        let today = calendar.startOfDay(for: Date())
        let monday = WeeklyAnalyticsMath.startOfISOWeek(containing: today, calendar: calendar)
        let days = calendar.dateComponents([.day], from: monday, to: today).day ?? 0
        return min(max(days, 0), 6)
    }
}

private struct WeekBarColumn: View {
    let letter: String
    let weekdayName: String
    let percent: Int?
    let isToday: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 36)

                if let percent {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isToday ? Color.green.opacity(0.85) : Color.primary.opacity(0.28))
                        .frame(height: max(CGFloat(percent) / 100 * 36, percent == 0 ? 0 : 1))
                        .overlay {
                            if isToday {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .stroke(Color.green, lineWidth: 1)
                            }
                        }
                } else {
                    Capsule()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(height: 2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .bottom)

            Text(letter)
                .font(.caption2.weight(isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(barAccessibilityValue))
        .help(barAccessibilityValue)
    }

    private var barAccessibilityValue: String {
        if let percent {
            return "\(weekdayName), \(percent) percent upright"
        }
        return "\(weekdayName), no data"
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

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
