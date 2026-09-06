import Foundation

public struct DayBucket: Codable, Equatable, Sendable {
    public private(set) var monitoredSeconds: Double
    public private(set) var offNeutralSeconds: Double
    public private(set) var countdownSeconds: Double
    public private(set) var slouchSeconds: Double
    public private(set) var slouchEpisodes: Int

    public init(monitoredSeconds: Double = 0, offNeutralSeconds: Double = 0, countdownSeconds: Double = 0, slouchSeconds: Double = 0, slouchEpisodes: Int = 0) {
        self.monitoredSeconds = monitoredSeconds
        self.offNeutralSeconds = offNeutralSeconds
        self.countdownSeconds = countdownSeconds
        self.slouchSeconds = slouchSeconds
        self.slouchEpisodes = slouchEpisodes
        precondition(isValid, "Invalid analytics durations")
    }

    public var uprightSeconds: Double { max(0, monitoredSeconds - offNeutralSeconds) }
    // Keep the same grouping as validation and total recomposition so a fully
    // classified fractional bucket cannot acquire a false legacy remainder.
    public var unsplitSeconds: Double { max(0, offNeutralSeconds - (countdownSeconds + slouchSeconds)) }
    public var percentUpright: Double? { monitoredSeconds > 0 ? 100 * (uprightSeconds / monitoredSeconds) : nil }

    private var isValid: Bool {
        [monitoredSeconds, offNeutralSeconds, countdownSeconds, slouchSeconds].allSatisfy { $0.isFinite && $0 >= 0 }
            && offNeutralSeconds <= monitoredSeconds
            && countdownSeconds + slouchSeconds <= offNeutralSeconds
            && slouchEpisodes >= 0
    }

    private enum CodingKeys: String, CodingKey {
        case monitoredSeconds, offNeutralSeconds, countdownSeconds, slouchSeconds, slouchEpisodes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitoredSeconds = try values.decode(Double.self, forKey: .monitoredSeconds)
        offNeutralSeconds = try values.decode(Double.self, forKey: .offNeutralSeconds)
        countdownSeconds = values.contains(.countdownSeconds) ? try values.decode(Double.self, forKey: .countdownSeconds) : 0
        slouchSeconds = values.contains(.slouchSeconds) ? try values.decode(Double.self, forKey: .slouchSeconds) : 0
        slouchEpisodes = try values.decode(Int.self, forKey: .slouchEpisodes)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid analytics durations or episode count"))
        }
    }

    fileprivate mutating func add(seconds: Double, state: AnalyticsState) {
        guard seconds.isFinite, seconds > 0, state != .inactive else { return }
        let upright = uprightSeconds + (state == .upright ? seconds : 0)
        let unsplit = unsplitSeconds
        if state == .countdown { countdownSeconds += seconds }
        if state == .slouch { slouchSeconds += seconds }
        // Recompose totals so floating-point additions cannot violate category bounds.
        offNeutralSeconds = (countdownSeconds + slouchSeconds) + unsplit
        monitoredSeconds = offNeutralSeconds + upright
    }

    fileprivate mutating func addEpisode() { slouchEpisodes += 1 }
}

public enum AnalyticsState: Equatable, Sendable {
    case inactive, upright, countdown, slouch
}

/// One complete scoring result; emitted after all scoring fields have been updated.
public struct AnalyticsObservation: Equatable, Sendable {
    public let state: AnalyticsState
    public let date: Date
    public let monotonic: TimeInterval

    public init(state: AnalyticsState, date: Date, monotonic: TimeInterval) {
        self.state = state
        self.date = date
        self.monotonic = monotonic
    }
}

public enum AnalyticsDocumentError: Error, Equatable {
    case unsupportedSchema(Int)
}

public struct AnalyticsDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let days: [String: DayBucket]

    public init(days: [String: DayBucket]) {
        schemaVersion = 2
        self.days = days
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, days }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 || version == 2 else { throw AnalyticsDocumentError.unsupportedSchema(version) }
        days = try values.decode([String: DayBucket].self, forKey: .days)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard days.keys.allSatisfy({ PostureAnalytics.parseDayKey($0, calendar: calendar) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid analytics day key"))
        }
        schemaVersion = 2
    }
}

public struct DayAnalytics: Equatable, Identifiable, Sendable {
    public let date: Date
    public let bucket: DayBucket
    public var id: Date { date }
    public var monitoredSeconds: Double { bucket.monitoredSeconds }
    public var uprightSeconds: Double { bucket.uprightSeconds }
    public var countdownSeconds: Double { bucket.countdownSeconds }
    public var slouchSeconds: Double { bucket.slouchSeconds }
    public var unsplitSeconds: Double { bucket.unsplitSeconds }
    public var uprightPercent: Double? { bucket.percentUpright }
    public var countdownPercent: Double? { percent(bucket.countdownSeconds) }
    public var slouchPercent: Double? { percent(bucket.slouchSeconds) }
    public var unsplitPercent: Double? { percent(bucket.unsplitSeconds) }

    public init(date: Date, bucket: DayBucket) { self.date = date; self.bucket = bucket }
    private func percent(_ seconds: Double) -> Double? { monitoredSeconds > 0 ? 100 * (seconds / monitoredSeconds) : nil }
}

public struct HistoryPoint: Equatable, Identifiable, Sendable {
    public let date: Date
    public let dailyPercent: Double?
    public let monitoredSeconds: Double
    public let trendPercent: Double?
    public let trendMonitoredSeconds: Double
    public let trendObservedDays: Int
    /// Changes after each missing date, allowing chart series to break at gaps.
    public let segmentID: Int
    public var id: Date { date }
}

public struct AnalyticsPeriod: Equatable, Sendable {
    public let monitoredSeconds: Double
    public let uprightSeconds: Double
    public let observedDays: Int
    public var percentUpright: Double? { monitoredSeconds > 0 ? 100 * (uprightSeconds / monitoredSeconds) : nil }
}

public struct AnalyticsComparison: Equatable, Sendable {
    public let latest: AnalyticsPeriod
    public let previous: AnalyticsPeriod
    public var changePoints: Double? {
        guard let latest = latest.percentUpright, let previous = previous.percentUpright else { return nil }
        return latest - previous
    }
}

public enum PostureAnalytics {
    public static let retentionDays = 90

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func parseDayKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, key.count == 10,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              dayKey(for: date, calendar: calendar) == key else { return nil }
        return date
    }

    public static func dates(ending date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: date)
        return (0..<min(count, retentionDays)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    public static func prune(days: [String: DayBucket], now: Date, calendar: Calendar = .current) -> [String: DayBucket] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: today) else { return days }
        return days.filter { key, _ in
            guard let date = parseDayKey(key, calendar: calendar) else { return false }
            return date >= cutoff && date <= today
        }
    }

    public static func period(days: [String: DayBucket], dates: [Date], calendar: Calendar = .current) -> AnalyticsPeriod {
        var monitored = 0.0
        var upright = 0.0
        var observed = 0
        for date in dates {
            guard let bucket = days[dayKey(for: date, calendar: calendar)], bucket.monitoredSeconds > 0 else { continue }
            monitored += bucket.monitoredSeconds
            upright += bucket.uprightSeconds
            observed += 1
        }
        return AnalyticsPeriod(monitoredSeconds: monitored, uprightSeconds: upright, observedDays: observed)
    }

    public static func history(days: [String: DayBucket], ending date: Date, count: Int, calendar: Calendar = .current) -> [HistoryPoint] {
        var segment = 0
        return dates(ending: date, count: count, calendar: calendar).map { date in
            let bucket = days[dayKey(for: date, calendar: calendar)] ?? DayBucket()
            let trailing = period(days: days, dates: dates(ending: date, count: 7, calendar: calendar), calendar: calendar)
            if bucket.monitoredSeconds == 0 { segment += 1 }
            return HistoryPoint(date: date, dailyPercent: bucket.percentUpright, monitoredSeconds: bucket.monitoredSeconds,
                                trendPercent: bucket.monitoredSeconds > 0 && trailing.observedDays >= 2 ? trailing.percentUpright : nil,
                                trendMonitoredSeconds: trailing.monitoredSeconds, trendObservedDays: trailing.observedDays, segmentID: segment)
        }
    }

    public static func comparison(days: [String: DayBucket], ending date: Date, calendar: Calendar = .current) -> AnalyticsComparison {
        let previousEnd = calendar.date(byAdding: .day, value: -7, to: date) ?? date
        return AnalyticsComparison(
            latest: period(days: days, dates: dates(ending: date, count: 7, calendar: calendar), calendar: calendar),
            previous: period(days: days, dates: dates(ending: previousEnd, count: 7, calendar: calendar), calendar: calendar)
        )
    }
}

/// Classifies the interval preceding a scoring event using its previous complete state.
/// Duration comes from uptime. Its local dates follow the interval's wall-clock anchor;
/// a wall-clock correction reanchors subsequent intervals without inventing elapsed time.
public struct AnalyticsAccumulator {
    public private(set) var days: [String: DayBucket]
    public private(set) var state: AnalyticsState = .inactive
    public var calendar: Calendar
    private var anchorDate: Date?
    private var anchorMonotonic: TimeInterval?
    private var lastMonotonic: TimeInterval?

    public init(days: [String: DayBucket] = [:], calendar: Calendar = .current) {
        self.days = days
        self.calendar = calendar
    }

    public mutating func observe(_ state: AnalyticsState, at date: Date, monotonic: TimeInterval) {
        guard date.timeIntervalSinceReferenceDate.isFinite, monotonic.isFinite,
              lastMonotonic.map({ monotonic >= $0 }) ?? true else { return }
        advance(to: date, monotonic: monotonic)
        if state == .slouch && self.state != .slouch {
            let key = PostureAnalytics.dayKey(for: date, calendar: calendar)
            var bucket = days[key] ?? DayBucket()
            bucket.addEpisode()
            days[key] = bucket
        }
        self.state = state
        anchorDate = state == .inactive ? nil : date
        anchorMonotonic = state == .inactive ? nil : monotonic
    }

    public mutating func advance(to date: Date, monotonic: TimeInterval) {
        guard date.timeIntervalSinceReferenceDate.isFinite, monotonic.isFinite,
              lastMonotonic.map({ monotonic >= $0 }) ?? true else { return }
        lastMonotonic = monotonic
        guard let anchorDate, let anchorMonotonic else { return }
        let elapsed = monotonic - anchorMonotonic
        guard elapsed >= 0, elapsed.isFinite else { return }
        var cursor = anchorDate
        var remaining = elapsed
        while remaining > 0 {
            guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { break }
            let seconds = min(remaining, nextMidnight.timeIntervalSince(cursor))
            guard seconds > 0 else { break }
            let key = PostureAnalytics.dayKey(for: cursor, calendar: calendar)
            var bucket = days[key] ?? DayBucket()
            bucket.add(seconds: seconds, state: state)
            days[key] = bucket
            remaining -= seconds
            cursor = nextMidnight
        }
        self.anchorDate = date
        self.anchorMonotonic = monotonic
    }

    public mutating func suspend(at date: Date, monotonic: TimeInterval) {
        observe(.inactive, at: date, monotonic: monotonic)
    }

    public mutating func prune(now: Date) {
        days = PostureAnalytics.prune(days: days, now: now, calendar: calendar)
    }
}
