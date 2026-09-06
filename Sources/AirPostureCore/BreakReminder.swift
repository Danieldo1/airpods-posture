import Foundation

public enum BreakKind: String, CaseIterable, Identifiable, Sendable {
    case walk, water, eyes, mix

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .walk: "Walk"
        case .water: "Water"
        case .eyes: "Eyes"
        case .mix: "Mix"
        }
    }
}

public struct BreakBanner: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum BreakReminder {
    public static let minIntervalMinutes = 5
    public static let maxIntervalMinutes = 120
    public static let defaultIntervalMinutes = 45
    public static let intervalStepMinutes = 5

    public static func clampIntervalMinutes(_ value: Double) -> Int {
        guard value.isFinite else { return defaultIntervalMinutes }
        let rounded = (value / Double(intervalStepMinutes)).rounded() * Double(intervalStepMinutes)
        return Int(min(Double(maxIntervalMinutes), max(Double(minIntervalMinutes), rounded)))
    }

    public static func nextFireDate(now: Date, intervalMinutes: Int) -> Date {
        now.addingTimeInterval(TimeInterval(clampIntervalMinutes(Double(intervalMinutes)) * 60))
    }

    public static func remainingSeconds(now: Date, nextFire: Date) -> Int {
        max(0, Int(ceil(nextFire.timeIntervalSince(now))))
    }

    public static func isDue(now: Date, nextFire: Date) -> Bool {
        now >= nextFire
    }

    public static func resolvedKind(_ kind: BreakKind, mixIndex: Int) -> BreakKind {
        guard kind == .mix else { return kind }
        return [BreakKind.walk, .water, .eyes][((mixIndex % 3) + 3) % 3]
    }

    public static func nextMixIndex(_ mixIndex: Int) -> Int {
        mixIndex &+ 1
    }

    public static func banner(kind: BreakKind, mixIndex: Int) -> BreakBanner {
        switch resolvedKind(kind, mixIndex: mixIndex) {
        case .walk, .mix:
            BreakBanner(title: "Time for a walk", body: "Stand up and take a short walk away from the screen.")
        case .water:
            BreakBanner(title: "Drink some water", body: "Take a sip and look away from the screen for a moment.")
        case .eyes:
            BreakBanner(title: "Rest your eyes", body: "Look away from the screen for 20 seconds.")
        }
    }

    public static func statusItemText(remainingSeconds: Int) -> String {
        let remaining = max(0, remainingSeconds)
        if remaining >= 3600 {
            return "\(remaining / 3600)h \(String(format: "%02d", remaining / 60 % 60))m"
        }
        if remaining >= 60 {
            return "\(remaining / 60)m"
        }
        return "0:\(String(format: "%02d", remaining))"
    }

    public static func popoverText(remainingSeconds: Int) -> String {
        let remaining = max(0, remainingSeconds)
        let seconds = String(format: "%02d", remaining % 60)
        if remaining >= 3600 {
            return "\(remaining / 3600):\(String(format: "%02d", remaining / 60 % 60)):\(seconds)"
        }
        return "\(remaining / 60):\(seconds)"
    }

    public static func accessibilityRemaining(remainingSeconds: Int) -> String {
        let remaining = max(0, remainingSeconds)
        if remaining >= 3600 {
            let hours = remaining / 3600
            let minutes = remaining / 60 % 60
            return "\(hours) \(hours == 1 ? "hour" : "hours") \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        if remaining >= 60 {
            let minutes = remaining / 60
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        return "\(remaining) \(remaining == 1 ? "second" : "seconds")"
    }
}
