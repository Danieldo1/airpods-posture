import AppKit
import Combine
import Foundation

struct DayBucket: Codable, Equatable {
    var monitoredSeconds: Int = 0
    var offNeutralSeconds: Int = 0
    var slouchEpisodes: Int = 0
}

struct WeekSummary: Equatable {
    var percentUpright: Int?
    var slouchEpisodes: Int
    var offNeutralMinutes: Int
    var vsLastWeekPoints: Int?
    var dailyUprightPercents: [Int?]
    var hasMonitoredTime: Bool

    static let empty = WeekSummary(
        percentUpright: nil,
        slouchEpisodes: 0,
        offNeutralMinutes: 0,
        vsLastWeekPoints: nil,
        dailyUprightPercents: Array(repeating: nil, count: 7),
        hasMonitoredTime: false
    )

    var summaryLine: String {
        guard hasMonitoredTime, let percentUpright else {
            return "No monitored time this week"
        }

        let episodeWord = slouchEpisodes == 1 ? "episode" : "episodes"
        var parts = [
            "\(percentUpright)% upright",
            "\(slouchEpisodes) slouch \(episodeWord)",
            "\(offNeutralMinutes) min off-neutral"
        ]
        if let vsLastWeekPoints {
            parts.append("\(Self.signedPoints(vsLastWeekPoints)) pts vs last week")
        }
        return parts.joined(separator: " · ")
    }

    private static func signedPoints(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "−\(abs(value))" }
        return "0"
    }
}

enum WeeklyAnalyticsMath {
    static let retentionDays = 90

    static func isoCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func parseDayKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func startOfISOWeek(containing date: Date, calendar: Calendar) -> Date {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) {
            return calendar.startOfDay(for: interval.start)
        }
        return calendar.startOfDay(for: date)
    }

    static func datesInWeek(starting monday: Date, calendar: Calendar) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    static func increment(
        _ bucket: DayBucket,
        monitored: Bool,
        offNeutral: Bool
    ) -> DayBucket {
        var next = bucket
        if monitored {
            next.monitoredSeconds += 1
            if offNeutral {
                next.offNeutralSeconds += 1
            }
        }
        return next
    }

    static func episodeEdge(
        eligible: Bool,
        wasSlouching: Bool,
        isSlouching: Bool
    ) -> (delta: Int, nextWasSlouching: Bool) {
        if !eligible {
            return (0, false)
        }
        let delta = (!wasSlouching && isSlouching) ? 1 : 0
        return (delta, isSlouching)
    }

    static func percentUpright(monitoredSeconds: Int, offNeutralSeconds: Int) -> Int? {
        guard monitoredSeconds > 0 else { return nil }
        return Int((100.0 * (1.0 - Double(offNeutralSeconds) / Double(monitoredSeconds))).rounded())
    }

    static func prune(
        days: [String: DayBucket],
        now: Date,
        calendar: Calendar = .current
    ) -> [String: DayBucket] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: today) else {
            return days
        }
        return days.filter { key, _ in
            guard let date = parseDayKey(key, calendar: calendar) else { return false }
            return date >= cutoff
        }
    }

    static func summarize(
        days: [String: DayBucket],
        now: Date,
        localCalendar: Calendar = .current,
        isoCalendar: Calendar
    ) -> WeekSummary {
        let thisMonday = startOfISOWeek(containing: now, calendar: isoCalendar)
        let thisWeekDates = datesInWeek(starting: thisMonday, calendar: localCalendar)
        let lastMonday = localCalendar.date(byAdding: .day, value: -7, to: thisMonday) ?? thisMonday
        let lastWeekDates = datesInWeek(starting: lastMonday, calendar: localCalendar)

        let thisWeek = totals(days: days, dates: thisWeekDates, calendar: localCalendar)
        let lastWeek = totals(days: days, dates: lastWeekDates, calendar: localCalendar)
        let thisPercent = percentUpright(
            monitoredSeconds: thisWeek.monitoredSeconds,
            offNeutralSeconds: thisWeek.offNeutralSeconds
        )
        let lastPercent = percentUpright(
            monitoredSeconds: lastWeek.monitoredSeconds,
            offNeutralSeconds: lastWeek.offNeutralSeconds
        )

        let daily = thisWeekDates.map { date in
            let bucket = days[dayKey(for: date, calendar: localCalendar)] ?? DayBucket()
            return percentUpright(
                monitoredSeconds: bucket.monitoredSeconds,
                offNeutralSeconds: bucket.offNeutralSeconds
            )
        }

        return WeekSummary(
            percentUpright: thisPercent,
            slouchEpisodes: thisWeek.slouchEpisodes,
            offNeutralMinutes: Int((Double(thisWeek.offNeutralSeconds) / 60.0).rounded()),
            vsLastWeekPoints: {
                guard let thisPercent, let lastPercent else { return nil }
                return thisPercent - lastPercent
            }(),
            dailyUprightPercents: daily,
            hasMonitoredTime: thisWeek.monitoredSeconds > 0
        )
    }

    private static func totals(
        days: [String: DayBucket],
        dates: [Date],
        calendar: Calendar
    ) -> DayBucket {
        dates.reduce(into: DayBucket()) { partial, date in
            let bucket = days[dayKey(for: date, calendar: calendar)] ?? DayBucket()
            partial.monitoredSeconds += bucket.monitoredSeconds
            partial.offNeutralSeconds += bucket.offNeutralSeconds
            partial.slouchEpisodes += bucket.slouchEpisodes
        }
    }
}

@MainActor
final class WeeklyAnalyticsStore: ObservableObject {
    @Published private(set) var weekSummary: WeekSummary = .empty
    @Published private(set) var lastStoreError: String?

    private let tracker: PostureTrackingManager
    private let fileURL: URL
    private let now: () -> Date
    private var days: [String: DayBucket] = [:]
    private var wasSlouching = false
    private var sampleTimer: Timer?
    private var samplesSinceFlush = 0
    private var consecutiveWriteFailures = 0
    private var cancellables: Set<AnyCancellable> = []
    private var terminateObserver: NSObjectProtocol?

    private enum Timing {
        static let sample: TimeInterval = 1
        static let flushEverySamples = 10
        static let failuresBeforeCaption = 3
    }

    init(
        tracker: PostureTrackingManager,
        fileURL: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.tracker = tracker
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
        load()
        refreshSummary()
        start()
    }

    deinit {
        sampleTimer?.invalidate()
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
    }

    private func start() {
        sampleTimer = Timer.scheduledTimer(withTimeInterval: Timing.sample, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        if let sampleTimer {
            RunLoop.main.add(sampleTimer, forMode: .common)
        }

        tracker.$isSlouching
            .removeDuplicates()
            .sink { [weak self] isSlouching in
                self?.applyEpisodeEdge(isSlouching: isSlouching)
                self?.refreshSummary()
            }
            .store(in: &cancellables)

        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flush(force: true)
            }
        }
    }

    private func sample() {
        let eligible = tracker.isAnalyticsEligible
        let key = WeeklyAnalyticsMath.dayKey(for: now())
        var bucket = days[key] ?? DayBucket()
        bucket = WeeklyAnalyticsMath.increment(
            bucket,
            monitored: eligible,
            offNeutral: eligible && tracker.isPastThreshold
        )
        applyEpisodeEdge(isSlouching: tracker.isSlouching, to: &bucket)
        days[key] = bucket
        samplesSinceFlush += 1
        if samplesSinceFlush >= Timing.flushEverySamples {
            flush(force: false)
        }
        refreshSummary()
    }

    private func applyEpisodeEdge(isSlouching: Bool) {
        let key = WeeklyAnalyticsMath.dayKey(for: now())
        var bucket = days[key] ?? DayBucket()
        applyEpisodeEdge(isSlouching: isSlouching, to: &bucket)
        days[key] = bucket
    }

    private func applyEpisodeEdge(isSlouching: Bool, to bucket: inout DayBucket) {
        let result = WeeklyAnalyticsMath.episodeEdge(
            eligible: tracker.isAnalyticsEligible,
            wasSlouching: wasSlouching,
            isSlouching: isSlouching
        )
        bucket.slouchEpisodes += result.delta
        wasSlouching = result.nextWasSlouching
    }

    private func refreshSummary() {
        weekSummary = WeeklyAnalyticsMath.summarize(
            days: days,
            now: now(),
            isoCalendar: WeeklyAnalyticsMath.isoCalendar()
        )
    }

    private func load() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(AnalyticsDocument.self, from: data)
            days = WeeklyAnalyticsMath.prune(days: document.days, now: now())
        } catch {
            quarantineCorruptFile()
            days = [:]
        }
    }

    private func flush(force: Bool) {
        samplesSinceFlush = 0
        days = WeeklyAnalyticsMath.prune(days: days, now: now())

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let document = AnalyticsDocument(schemaVersion: 1, days: days)
            let data = try JSONEncoder().encode(document)
            let temporaryURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("weekly-analytics.json.tmp")
            try data.write(to: temporaryURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
            }
            consecutiveWriteFailures = 0
            lastStoreError = nil
        } catch {
            consecutiveWriteFailures += 1
            if consecutiveWriteFailures >= Timing.failuresBeforeCaption {
                lastStoreError = "Couldn’t save this week’s stats. AirPosture will keep them in memory and try again."
            }
            if force {
                return
            }
        }
    }

    private func quarantineCorruptFile() {
        let stamp = Int(now().timeIntervalSince1970)
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("weekly-analytics.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root
            .appendingPathComponent("AirPosture", isDirectory: true)
            .appendingPathComponent("weekly-analytics.json")
    }
}

private struct AnalyticsDocument: Codable {
    var schemaVersion: Int
    var days: [String: DayBucket]
}
