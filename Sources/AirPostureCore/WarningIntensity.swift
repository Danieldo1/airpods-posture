import Foundation

public struct OverlayColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public static let warm = OverlayColor(red: 1.00, green: 0.62, blue: 0.11)
    public static let cool = OverlayColor(red: 0.18, green: 0.70, blue: 0.68)
    public static let alert = OverlayColor(red: 0.91, green: 0.22, blue: 0.21)

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.validComponent(red)
        self.green = Self.validComponent(green)
        self.blue = Self.validComponent(blue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        guard Self.isValidComponent(red), Self.isValidComponent(green), Self.isValidComponent(blue) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "sRGB components must be finite values from zero through one.")
            )
        }
        self.red = red
        self.green = green
        self.blue = blue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
    }

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    private static func validComponent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func isValidComponent(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }
}

public enum WarningIntensity {
    public static func target(
        deviation: Double,
        graceProgress: Double,
        isSlouching: Bool,
        earlyEnabled: Bool,
        onset: Double
    ) -> Double {
        if isSlouching {
            return 1
        }
        guard earlyEnabled else {
            return 0
        }

        let deviation = finiteClamped(deviation, fallback: 0, range: 0...Double.greatestFiniteMagnitude)
        let graceProgress = finiteClamped(graceProgress, fallback: 0, range: 0...1)
        let onset = finiteClamped(onset, fallback: 0.7, range: 0.1...1)

        if deviation >= 1 {
            return 0.25 + 0.75 * smoothstep(graceProgress)
        }
        guard onset < 1, deviation > onset else {
            return 0
        }

        let progress = (deviation - onset) / (1 - onset)
        return 0.25 * smoothstep(progress)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let value = min(max(value, 0), 1)
        return value * value * (3 - 2 * value)
    }

    private static func finiteClamped(
        _ value: Double,
        fallback: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

public struct WarningEnvelope: Sendable {
    public private(set) var value: Double = 0

    private var zeroFadeStart: Double?
    private var zeroFadeElapsed: Double = 0

    public init() {}

    public mutating func update(
        target: Double,
        elapsed: Double,
        fadeIn: Double,
        reduceMotion: Bool
    ) -> Double {
        let target = Self.unitValue(target)
        if reduceMotion {
            value = target
            clearZeroFade()
            return value
        }

        let elapsed = elapsed.isFinite ? max(elapsed, 0) : 0
        if target == 0 {
            guard value > 0 else {
                value = 0
                clearZeroFade()
                return value
            }
            if zeroFadeStart == nil {
                zeroFadeStart = value
                zeroFadeElapsed = 0
            }
            zeroFadeElapsed += elapsed
            let progress = min(zeroFadeElapsed / 0.35, 1)
            value = (zeroFadeStart ?? value) * (1 - progress)
            if progress == 1 {
                value = 0
                clearZeroFade()
            }
            return value
        }

        clearZeroFade()
        guard elapsed > 0, target != value else {
            return value
        }

        let responseTime: Double
        if target < value {
            responseTime = 0.35
        } else if fadeIn.isFinite {
            responseTime = min(max(fadeIn, 0.5), 10)
        } else {
            responseTime = 3
        }
        let timeConstant = responseTime / log(20)
        let response = 1 - exp(-elapsed / timeConstant)
        value += (target - value) * response
        value = Self.unitValue(value)
        return value
    }

    public mutating func reset() {
        value = 0
        clearZeroFade()
    }

    private mutating func clearZeroFade() {
        zeroFadeStart = nil
        zeroFadeElapsed = 0
    }

    private static func unitValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

public struct WarningPresentationState: Sendable {
    private var envelope = WarningEnvelope()
    private var referenceID: String?

    public init() {}

    public mutating func update(
        target: Double,
        elapsed: Double,
        fadeIn: Double,
        reduceMotion: Bool,
        isEligible: Bool,
        referenceID: String
    ) -> Double {
        let referenceChanged = self.referenceID.map { $0 != referenceID } ?? false
        self.referenceID = referenceID
        guard isEligible, !referenceChanged else {
            envelope.reset()
            return 0
        }
        return envelope.update(
            target: target,
            elapsed: elapsed,
            fadeIn: fadeIn,
            reduceMotion: reduceMotion
        )
    }

    public mutating func reset() {
        envelope.reset()
        referenceID = nil
    }
}
