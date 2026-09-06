#if SWIFT_PACKAGE
import AirPostureCore
#endif
import AppKit
import Combine
import Foundation

struct WeekSummary: Equatable {
    var percentUpright: Int?
    var slouchEpisodes: Int
    var offNeutralMinutes: Int
    var vsLastWeekPoints: Int?
    var dailyUprightPercents: [Int?]
    var hasMonitoredTime: Bool
    var dailyDetails: [DayAnalytics] = []

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
    static func isoCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    static func startOfISOWeek(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func summarize(days: [String: DayBucket], now: Date, localCalendar: Calendar = .current, isoCalendar: Calendar) -> WeekSummary {
        let monday = startOfISOWeek(containing: now, calendar: isoCalendar)
        let dates = (0..<7).compactMap { localCalendar.date(byAdding: .day, value: $0, to: monday) }
        let previousDates = dates.compactMap { localCalendar.date(byAdding: .day, value: -7, to: $0) }
        let today = localCalendar.startOfDay(for: now)
        let details = dates.map { date in
            DayAnalytics(date: date, bucket: date <= today ? days[PostureAnalytics.dayKey(for: date, calendar: localCalendar)] ?? DayBucket() : DayBucket())
        }
        let current = PostureAnalytics.period(days: days, dates: dates.filter { $0 <= today }, calendar: localCalendar)
        let previous = PostureAnalytics.period(days: days, dates: previousDates, calendar: localCalendar)
        let percent = current.percentUpright.map { Int($0.rounded()) }
        let previousPercent = previous.percentUpright.map { Int($0.rounded()) }
        return WeekSummary(
            percentUpright: percent,
            slouchEpisodes: details.reduce(0) { $0 + $1.bucket.slouchEpisodes },
            offNeutralMinutes: Int((details.reduce(0) { $0 + $1.bucket.offNeutralSeconds } / 60).rounded()),
            vsLastWeekPoints: percent.flatMap { current in previousPercent.map { current - $0 } },
            dailyUprightPercents: details.map { $0.uprightPercent.map { Int($0.rounded()) } },
            hasMonitoredTime: current.monitoredSeconds > 0,
            dailyDetails: details
        )
    }
}

@MainActor
final class WeeklyAnalyticsStore: ObservableObject {
    @Published private(set) var weekSummary: WeekSummary = .empty
    @Published private(set) var periodComparison: AnalyticsComparison
    @Published private(set) var lastStoreError: String?

    private let fileURL: URL
    private let now: () -> Date
    private let monotonic: () -> TimeInterval
    private let lifecycleCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private var accumulator: AnalyticsAccumulator
    private var sampleTimer: Timer?
    private var samplesSinceFlush = 0
    private var isSleeping = false
    private var protectsOriginalFile = false
    private var cancellables: Set<AnyCancellable> = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    convenience init(tracker: PostureTrackingManager, fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.init(observations: tracker.analyticsObservations.eraseToAnyPublisher(),
                  fileURL: fileURL ?? Self.defaultFileURL(), now: now)
    }

    init(
        observations: AnyPublisher<AnalyticsObservation, Never>,
        fileURL: URL,
        now: @escaping () -> Date = Date.init,
        monotonic: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        calendar: Calendar = .autoupdatingCurrent,
        lifecycleCenter: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.fileURL = fileURL
        self.now = now
        self.monotonic = monotonic
        self.lifecycleCenter = lifecycleCenter
        self.workspaceCenter = workspaceCenter
        accumulator = AnalyticsAccumulator(calendar: calendar)
        periodComparison = PostureAnalytics.comparison(days: [:], ending: now(), calendar: calendar)
        load()
        refreshSummary()
        observations.sink { [weak self] observation in
            guard let self, !self.isSleeping else { return }
            self.accumulator.observe(observation.state, at: observation.date, monotonic: observation.monotonic)
        }.store(in: &cancellables)
        start()
    }

    deinit {
        sampleTimer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    func history(days: Int) -> [HistoryPoint] {
        PostureAnalytics.history(days: accumulator.days, ending: now(), count: days, calendar: accumulator.calendar)
    }

    private func start() {
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if let sampleTimer { RunLoop.main.add(sampleTimer, forMode: .common) }
        observe(lifecycleCenter, name: NSApplication.willTerminateNotification) { $0.flush() }
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification) { store in
            store.accumulator.suspend(at: store.now(), monotonic: store.monotonic())
            store.isSleeping = true
            store.flush()
        }
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { store in
            // The accumulator remains inactive until a fresh scoring observation arrives.
            store.isSleeping = false
            store.refreshSummary()
        }
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name, action: @escaping @MainActor (WeeklyAnalyticsStore) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    private func sample() {
        accumulator.advance(to: now(), monotonic: monotonic())
        samplesSinceFlush += 1
        if samplesSinceFlush >= 10 { flush() }
        else { refreshSummary() }
    }

    private func refreshSummary() {
        let date = now()
        weekSummary = WeeklyAnalyticsMath.summarize(days: accumulator.days, now: date, localCalendar: accumulator.calendar,
            isoCalendar: WeeklyAnalyticsMath.isoCalendar(timeZone: accumulator.calendar.timeZone))
        periodComparison = PostureAnalytics.comparison(days: accumulator.days, ending: date, calendar: accumulator.calendar)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(AnalyticsDocument.self, from: data)
            accumulator = AnalyticsAccumulator(days: PostureAnalytics.prune(days: document.days, now: now(), calendar: accumulator.calendar), calendar: accumulator.calendar)
        } catch AnalyticsDocumentError.unsupportedSchema(let version) {
            protectsOriginalFile = true
            lastStoreError = "History uses unsupported version \(version). The original file is untouched. Update AirPosture or move \(fileURL.lastPathComponent) to save new history."
        } catch is DecodingError {
            quarantineCorruptFile()
        } catch {
            protectsOriginalFile = true
            lastStoreError = "Couldn’t read history. Check access to \(fileURL.path). The original file is untouched."
        }
    }

    private func flush() {
        accumulator.advance(to: now(), monotonic: monotonic())
        accumulator.prune(now: now())
        samplesSinceFlush = 0
        refreshSummary()
        if protectsOriginalFile && FileManager.default.fileExists(atPath: fileURL.path) { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(AnalyticsDocument(days: accumulator.days))
            try data.write(to: fileURL, options: .atomic)
            protectsOriginalFile = false
            lastStoreError = nil
        } catch {
            lastStoreError = "Couldn’t save history. AirPosture will keep it in memory and retry. Check access and free space at \(fileURL.deletingLastPathComponent().path)."
            NSLog("AirPosture analytics write failed: %@", String(describing: error))
        }
    }

    private func quarantineCorruptFile() {
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent("weekly-analytics.corrupt-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            lastStoreError = "Couldn’t read history. The original was saved as \(destination.lastPathComponent). New history will be saved separately."
        } catch {
            protectsOriginalFile = true
            lastStoreError = "Couldn’t read or back up history. Move \(fileURL.path) to a safe location to save new history."
        }
    }

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return root.appendingPathComponent("AirPosture", isDirectory: true).appendingPathComponent("weekly-analytics.json")
    }
}
