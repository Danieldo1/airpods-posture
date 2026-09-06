import SwiftUI
import Charts
#if SWIFT_PACKAGE
import AirPostureCore
#endif

/// Shared formatting keeps short recordings meaningful in summaries and detail cards.
enum AnalyticsDisplay {
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "0s" }
        if seconds < 1 { return "<1s" }
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
    static func percent(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(1))))%" }
    static func date(_ value: Date) -> String { value.formatted(.dateTime.weekday(.wide).month(.wide).day().year()) }
}

struct PostureAnalyticsView: View {
    @ObservedObject var store: WeeklyAnalyticsStore
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDay: Date?
    @State private var hoveredDay: Date?
    @State private var range = 30
    @State private var selectedHistoryDate: Date?
    @State private var hoveredHistoryDate: Date?

    private var summary: WeekSummary { store.weekSummary }
    private var history: [HistoryPoint] { store.history(days: range) }
    private var dayDetail: DayAnalytics? {
        summary.dailyDetails.first { $0.date == (hoveredDay ?? selectedDay) }
            ?? summary.dailyDetails.last { Calendar.current.isDateInToday($0.date) }
    }
    private var historyDetail: HistoryPoint? { historyDetail(in: history) }
    private func historyDetail(in points: [HistoryPoint]) -> HistoryPoint? {
        let target = hoveredHistoryDate ?? selectedHistoryDate
        return points.min { abs($0.date.timeIntervalSince(target ?? Date())) < abs($1.date.timeIntervalSince(target ?? Date())) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureHeader(title: "This week", subtitle: summary.hasMonitoredTime ? "Your posture at a glance" : "No monitored time yet",
                             systemImage: "chart.bar.xaxis", isExpanded: isExpanded) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isExpanded.toggle() }
            }
            if summary.hasMonitoredTime {
                HStack(spacing: 8) {
                    SummaryMetric(value: summary.percentUpright.map { "\($0)%" } ?? "—", label: "Upright", tint: .green)
                    SummaryMetric(value: "\(summary.slouchEpisodes)", label: summary.slouchEpisodes == 1 ? "Slouch" : "Slouches", tint: .orange)
                    SummaryMetric(value: AnalyticsDisplay.duration(summary.dailyDetails.reduce(0) { $0 + $1.bucket.offNeutralSeconds }),
                                  label: "Off-neutral", tint: .secondary)
                }
            }
            if isExpanded {
                weeklyChart
                historySection
            }
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily time breakdown").font(.subheadline.weight(.semibold))
                Spacer()
                Text("0–100%").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(summary.dailyDetails) { day in
                    Button { selectedDay = day.date } label: {
                        VStack(spacing: 6) {
                            GeometryReader { geometry in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                    if day.monitoredSeconds > 0 {
                                        VStack(spacing: 0) {
                                            segment(.gray, seconds: day.unsplitSeconds, day: day, height: geometry.size.height)
                                            segment(.red, seconds: day.slouchSeconds, day: day, height: geometry.size.height)
                                            segment(.orange, seconds: day.countdownSeconds, day: day, height: geometry.size.height)
                                            segment(.green, seconds: day.uprightSeconds, day: day, height: geometry.size.height)
                                        }.clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text("—").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }.frame(height: 78)
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption.weight(Calendar.current.isDateInToday(day.date) ? .bold : .regular))
                            Circle().fill(Calendar.current.isDateInToday(day.date) ? Color.primary : .clear).frame(width: 4, height: 4)
                        }
                        .padding(3)
                        .background(dayDetail?.date == day.date ? Color.primary.opacity(0.07) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredDay = $0 ? day.date : nil }
                    .accessibilityLabel(dayAccessibility(day))
                    .accessibilityHint("Select to show daily details")
                    .accessibilityAddTraits(selectedDay == day.date ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Monday through Sunday, percentage of monitored time")
            VStack(alignment: .leading, spacing: 5) {
                HStack { legend("Within sensitivity", color: .green); Spacer(); legend("Countdown", color: .orange) }
                HStack { legend("Sustained slouch", color: .red); Spacer() }
                if summary.dailyDetails.contains(where: { $0.unsplitSeconds > 0 }) {
                    legend("Earlier off-neutral, unsplit", color: .gray)
                }
            }
            if let day = dayDetail { dailyDetails(day) }
        }
        .padding(.top, 4)
    }

    private func segment(_ color: Color, seconds: Double, day: DayAnalytics, height: CGFloat) -> some View {
        color.frame(height: height * seconds / day.monitoredSeconds)
    }

    private func dailyDetails(_ day: DayAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AnalyticsDisplay.date(day.date)).font(.caption.weight(.semibold))
            if Calendar.current.isDateInToday(day.date) { Text("Today · in progress").font(.caption2).foregroundStyle(.secondary) }
            Text("Monitored \(AnalyticsDisplay.duration(day.monitoredSeconds))").font(.caption)
            if day.monitoredSeconds > 0 {
                durationRow("Within sensitivity", seconds: day.uprightSeconds, percent: day.uprightPercent, color: .green)
                durationRow("Countdown", seconds: day.countdownSeconds, percent: day.countdownPercent, color: .orange)
                durationRow("Sustained slouch", seconds: day.slouchSeconds, percent: day.slouchPercent, color: .red)
                if day.unsplitSeconds > 0 {
                    durationRow("Earlier off-neutral", seconds: day.unsplitSeconds, percent: day.unsplitPercent, color: .gray)
                    Text("Older recordings did not separate countdown from sustained slouch.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text("No monitored time").font(.caption).foregroundStyle(.secondary) }
            Text("\(day.bucket.slouchEpisodes) slouch episodes").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var historySection: some View {
        // Project once per render; do not recompute 90-day history for every chart mark.
        let points = history
        let selectedPoint = historyDetail(in: points)
        return VStack(alignment: .leading, spacing: 10) {
            Divider().padding(.vertical, 4)
            HStack {
                Text("History").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("History range", selection: $range) {
                    Text("7d").tag(7); Text("30d").tag(30); Text("90d").tag(90)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("History range")
                .frame(width: 170)
            }
            Chart(points) { point in
                if point.date == selectedPoint?.date {
                    RuleMark(x: .value("Selected date", point.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                if let percent = point.dailyPercent {
                    LineMark(x: .value("Date", point.date), y: .value("Within sensitivity", percent),
                             series: .value("Daily segment", "daily-\(point.segmentID)"))
                        .foregroundStyle(Color.green).lineStyle(StrokeStyle(lineWidth: 1.5))
                    PointMark(x: .value("Date", point.date), y: .value("Within sensitivity", percent))
                        .foregroundStyle(Color.green).symbolSize(14)
                }
                if let trend = point.trendPercent {
                    LineMark(x: .value("Date", point.date), y: .value("7-day trend", trend),
                             series: .value("Trend segment", "trend-\(point.segmentID)"))
                        .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    PointMark(x: .value("Date", point.date), y: .value("7-day trend", trend))
                        .foregroundStyle(Color.blue).symbolSize(8)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: (points.first?.date ?? Date())...(points.last?.date ?? Date()))
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine(); AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%") } }
            } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedHistoryDate)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { return }
                                let plot = geometry[frame]
                                hoveredHistoryDate = plot.contains(location) ? proxy.value(atX: location.x - plot.minX, as: Date.self) : nil
                            case .ended: hoveredHistoryDate = nil
                            }
                        }
                        .onTapGesture { location in
                            guard let frame = proxy.plotFrame else { return }
                            let plot = geometry[frame]
                            if plot.contains(location) { selectedHistoryDate = proxy.value(atX: location.x - plot.minX, as: Date.self) }
                        }
                }
            }
            .frame(height: 135)
            .overlay {
                if !points.contains(where: { $0.dailyPercent != nil }) {
                    Text("No monitored time in this range")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Daily and duration-weighted seven-day trend, zero to one hundred percent. Use the date control for exact details.")
            HStack { legend("Daily", color: .green); Spacer(); legend("7-day weighted trend", color: .blue, dashed: true) }
            if let detail = selectedPoint {
                HStack(spacing: 6) {
                    Button { moveHistory(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous history day")
                        .disabled(detail.date == points.first?.date)
                    Picker("History date", selection: Binding(get: { detail.date }, set: { selectedHistoryDate = $0; hoveredHistoryDate = nil })) {
                        ForEach(points) { point in Text(point.date.formatted(date: .abbreviated, time: .omitted)).tag(point.date) }
                    }.labelsHidden().pickerStyle(.menu)
                    Button { moveHistory(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next history day")
                        .disabled(detail.date == points.last?.date)
                }.controlSize(.small)
                historyDetails(detail)
            }
            comparison
            Text("Higher means more time within your sensitivity settings.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: range) { _, _ in selectedHistoryDate = nil; hoveredHistoryDate = nil }
    }

    private func historyDetails(_ point: HistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AnalyticsDisplay.date(point.date)).font(.caption.weight(.semibold))
            if let daily = point.dailyPercent {
                Text("\(AnalyticsDisplay.percent(daily)) within sensitivity · \(AnalyticsDisplay.duration(point.monitoredSeconds)) monitored")
                if let trend = point.trendPercent { Text("7-day trend: \(AnalyticsDisplay.percent(trend))") }
                else { Text("Trend needs at least 2 observed days") }
                Text("Trend coverage: \(point.trendObservedDays)/7 days · \(AnalyticsDisplay.duration(point.trendMonitoredSeconds))")
                    .foregroundStyle(.secondary)
            } else { Text("No monitored time on this date").foregroundStyle(.secondary) }
        }
        .font(.caption).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var comparison: some View {
        let comparison = store.periodComparison
        return VStack(alignment: .leading, spacing: 5) {
            if let change = comparison.changePoints {
                Text("\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) points vs preceding 7 days")
                    .font(.caption.weight(.semibold))
                Text("Latest 7 days: \(AnalyticsDisplay.percent(comparison.latest.percentUpright ?? 0)) · \(comparison.latest.observedDays)/7 days · \(AnalyticsDisplay.duration(comparison.latest.monitoredSeconds))")
                Text("Preceding 7 days: \(AnalyticsDisplay.percent(comparison.previous.percentUpright ?? 0)) · \(comparison.previous.observedDays)/7 days · \(AnalyticsDisplay.duration(comparison.previous.monitoredSeconds))")
            } else {
                Text("More history needed for a 7-day comparison").font(.caption.weight(.semibold))
                Text("Both seven-day periods need monitored time.")
            }
        }
        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func moveHistory(_ offset: Int) {
        guard let detail = historyDetail, let index = history.firstIndex(where: { $0.date == detail.date }) else { return }
        selectedHistoryDate = history[min(max(index + offset, 0), history.count - 1)].date
        hoveredHistoryDate = nil
    }

    private func legend(_ title: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            if dashed { Capsule().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 12, height: 2) }
            else { Circle().fill(color).frame(width: 6, height: 6) }
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func durationRow(_ title: String, seconds: Double, percent: Double?, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
            Spacer(minLength: 2)
            Text("\(AnalyticsDisplay.duration(seconds)) · \(AnalyticsDisplay.percent(percent ?? 0))").monospacedDigit()
        }.font(.caption2)
    }

    private func dayAccessibility(_ day: DayAnalytics) -> String {
        let today = Calendar.current.isDateInToday(day.date) ? ", today in progress" : ""
        guard day.monitoredSeconds > 0 else { return "\(AnalyticsDisplay.date(day.date))\(today), no monitored time, \(day.bucket.slouchEpisodes) slouch episodes" }
        var text = "\(AnalyticsDisplay.date(day.date))\(today), monitored \(AnalyticsDisplay.duration(day.monitoredSeconds)). "
        text += "Within sensitivity \(AnalyticsDisplay.duration(day.uprightSeconds)), \(AnalyticsDisplay.percent(day.uprightPercent ?? 0)). "
        text += "Countdown \(AnalyticsDisplay.duration(day.countdownSeconds)), \(AnalyticsDisplay.percent(day.countdownPercent ?? 0)). "
        text += "Sustained slouch \(AnalyticsDisplay.duration(day.slouchSeconds)), \(AnalyticsDisplay.percent(day.slouchPercent ?? 0)). "
        if day.unsplitSeconds > 0 {
            text += "Earlier off-neutral unsplit \(AnalyticsDisplay.duration(day.unsplitSeconds)), \(AnalyticsDisplay.percent(day.unsplitPercent ?? 0)). Older recordings did not separate countdown from sustained slouch. "
        }
        return text + "\(day.bucket.slouchEpisodes) slouch episodes."
    }
}
