import Foundation

enum WarningStyle: String, CaseIterable, Identifiable {
    case glow
    case border
    case dim
    case blur
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glow: "Glow"
        case .border: "Border"
        case .dim: "Dim"
        case .blur: "Blur"
        case .off: "Off"
        }
    }
}

enum OverlayTint: String, CaseIterable, Identifiable {
    case warm
    case cool
    case alert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warm: "Warm"
        case .cool: "Cool"
        case .alert: "Alert"
        }
    }
}

enum SoundPack: String, CaseIterable, Identifiable {
    case pop
    case tink
    case purr
    case bottle
    case morse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pop: "Pop"
        case .tink: "Tink"
        case .purr: "Purr"
        case .bottle: "Bottle"
        case .morse: "Morse"
        }
    }

    var systemSoundName: String {
        title
    }

    var systemSoundURL: URL {
        URL(fileURLWithPath: "/System/Library/Sounds/\(systemSoundName).aiff")
    }
}

enum IconFamily: String, CaseIterable, Identifiable {
    case postureFigure
    case horizonCross
    case minimalDot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .postureFigure: "Posture figure"
        case .horizonCross: "Horizon cross"
        case .minimalDot: "Minimal dot"
        }
    }
}

enum PosturePreset: String, CaseIterable, Identifiable {
    case desk
    case sofa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desk: "Desk"
        case .sofa: "Sofa"
        }
    }
}

@MainActor
final class AirPostureSettings: ObservableObject {
    @Published var warningStyle: WarningStyle {
        didSet { defaults.set(warningStyle.rawValue, forKey: Key.warningStyle) }
    }

    @Published var maxOverlayStrength: Double {
        didSet {
            let value = Self.clamped(maxOverlayStrength, min: Strength.min, max: Strength.max)
            if value != maxOverlayStrength {
                maxOverlayStrength = value
                return
            }
            defaults.set(value, forKey: Key.maxOverlayStrength)
        }
    }

    @Published var overlayTint: OverlayTint {
        didSet { defaults.set(overlayTint.rawValue, forKey: Key.overlayTint) }
    }

    @Published var soundPack: SoundPack {
        didSet { defaults.set(soundPack.rawValue, forKey: Key.soundPack) }
    }

    @Published var soundVolume: Double {
        didSet {
            let value = Self.clamped(soundVolume, min: Volume.min, max: Volume.max)
            if value != soundVolume {
                soundVolume = value
                return
            }
            defaults.set(value, forKey: Key.soundVolume)
        }
    }

    @Published var soundAfterDoubleGrace: Bool {
        didSet { defaults.set(soundAfterDoubleGrace, forKey: Key.soundAfterDoubleGrace) }
    }

    @Published var iconFamily: IconFamily {
        didSet { defaults.set(iconFamily.rawValue, forKey: Key.iconFamily) }
    }

    @Published var sitUpChimeEnabled: Bool {
        didSet { defaults.set(sitUpChimeEnabled, forKey: Key.sitUpChimeEnabled) }
    }

    @Published var snoozeEndsAt: Date?

    var isSnoozed: Bool {
        snoozeEndsAt.map { $0 > Date() } ?? false
    }

    private let defaults: UserDefaults

    private enum Key {
        static let warningStyle = "warningStyle"
        static let maxOverlayStrength = "maxOverlayStrength"
        static let overlayTint = "overlayTint"
        static let soundPack = "soundPack"
        static let soundVolume = "soundVolume"
        static let soundAfterDoubleGrace = "soundAfterDoubleGrace"
        static let iconFamily = "iconFamily"
        static let sitUpChimeEnabled = "sitUpChimeEnabled"
    }

    private enum Strength {
        static let min = 0.20
        static let max = 1.00
        static let fallback = 0.70
    }

    private enum Volume {
        static let min = 0.10
        static let max = 0.80
        static let fallback = 0.45
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.warningStyle: WarningStyle.glow.rawValue,
            Key.maxOverlayStrength: Strength.fallback,
            Key.overlayTint: OverlayTint.warm.rawValue,
            Key.soundPack: SoundPack.pop.rawValue,
            Key.soundVolume: Volume.fallback,
            Key.soundAfterDoubleGrace: false,
            Key.iconFamily: IconFamily.postureFigure.rawValue,
            Key.sitUpChimeEnabled: false
        ])

        warningStyle = Self.decode(defaults.string(forKey: Key.warningStyle), fallback: .glow)
        maxOverlayStrength = Self.clamped(
            defaults.double(forKey: Key.maxOverlayStrength),
            min: Strength.min,
            max: Strength.max,
            fallback: Strength.fallback
        )
        overlayTint = Self.decode(defaults.string(forKey: Key.overlayTint), fallback: .warm)
        soundPack = Self.decode(defaults.string(forKey: Key.soundPack), fallback: .pop)
        soundVolume = Self.clamped(
            defaults.double(forKey: Key.soundVolume),
            min: Volume.min,
            max: Volume.max,
            fallback: Volume.fallback
        )
        soundAfterDoubleGrace = defaults.bool(forKey: Key.soundAfterDoubleGrace)
        iconFamily = Self.decode(defaults.string(forKey: Key.iconFamily), fallback: .postureFigure)
        sitUpChimeEnabled = defaults.bool(forKey: Key.sitUpChimeEnabled)
    }

    func snooze(minutes: Int) {
        snoozeEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func snoozeUntilTomorrow() {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        snoozeEndsAt = calendar.date(byAdding: .day, value: 1, to: startOfToday)
    }

    func clearSnooze() {
        snoozeEndsAt = nil
    }

    func clearExpiredSnooze() {
        guard let snoozeEndsAt, snoozeEndsAt <= Date() else { return }
        self.snoozeEndsAt = nil
    }

    private static func decode<T: RawRepresentable>(_ raw: String?, fallback: T) -> T where T.RawValue == String {
        raw.flatMap(T.init(rawValue:)) ?? fallback
    }

    private static func clamped(_ value: Double, min: Double, max: Double, fallback: Double = 0) -> Double {
        if value == 0 { return fallback == 0 ? min : fallback }
        return Swift.min(Swift.max(value, min), max)
    }
}
