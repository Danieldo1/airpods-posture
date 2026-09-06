import Foundation
#if SWIFT_PACKAGE
import AirPostureCore
#endif

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
        didSet {
            defaults.set(warningStyle.rawValue, forKey: Key.warningStyle)
            if warningStyle != oldValue, warningStyle != .off {
                loadAppearance(for: warningStyle)
            }
        }
    }

    @Published var earlyCueEnabled: Bool {
        didSet { defaults.set(earlyCueEnabled, forKey: Key.earlyCueEnabled) }
    }

    @Published var cueStartFraction: Double {
        didSet {
            let value = Self.finiteClamped(
                cueStartFraction,
                min: Cue.minStartFraction,
                max: Cue.maxStartFraction,
                fallback: Cue.defaultStartFraction
            )
            if value != cueStartFraction {
                cueStartFraction = value
                defaults.set(value, forKey: Key.cueStartFraction)
                return
            }
            defaults.set(value, forKey: Key.cueStartFraction)
        }
    }

    @Published var overlayFadeInSeconds: Double {
        didSet {
            let value = Self.finiteClamped(
                overlayFadeInSeconds,
                min: Cue.minFadeIn,
                max: Cue.maxFadeIn,
                fallback: Cue.defaultFadeIn
            )
            if value != overlayFadeInSeconds {
                overlayFadeInSeconds = value
                defaults.set(value, forKey: Key.overlayFadeInSeconds)
                return
            }
            defaults.set(value, forKey: Key.overlayFadeInSeconds)
        }
    }

    @Published var maxOverlayStrength: Double {
        didSet {
            let value = Self.finiteClamped(
                maxOverlayStrength,
                min: Strength.min,
                max: Strength.max,
                fallback: Self.defaultStrength(for: warningStyle)
            )
            if value != maxOverlayStrength {
                maxOverlayStrength = value
                guard !isApplyingAppearance, warningStyle != .off else { return }
                defaults.set(value, forKey: Key.strength(for: warningStyle))
                defaults.set(value, forKey: Key.maxOverlayStrength)
                return
            }
            guard !isApplyingAppearance, warningStyle != .off else { return }
            defaults.set(value, forKey: Key.strength(for: warningStyle))
            defaults.set(value, forKey: Key.maxOverlayStrength)
        }
    }

    @Published var overlayTint: OverlayTint {
        didSet {
            defaults.set(overlayTint.rawValue, forKey: Key.overlayTint)
            guard !isApplyingAppearance, warningStyle != .off else { return }
            overlayColor = overlayTint.color
        }
    }

    @Published var overlayColor: OverlayColor {
        didSet {
            guard !isApplyingAppearance, warningStyle != .off else { return }
            persist(color: overlayColor, for: warningStyle)
            if let preset = OverlayTint(color: overlayColor), preset != overlayTint {
                overlayTint = preset
            }
        }
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

    @Published var breakRemindersEnabled: Bool {
        didSet { defaults.set(breakRemindersEnabled, forKey: Key.breakRemindersEnabled) }
    }

    @Published var breakIntervalMinutes: Double {
        didSet {
            let value = Double(BreakReminder.clampIntervalMinutes(breakIntervalMinutes))
            if value != breakIntervalMinutes {
                breakIntervalMinutes = value
                defaults.set(value, forKey: Key.breakIntervalMinutes)
                return
            }
            defaults.set(value, forKey: Key.breakIntervalMinutes)
        }
    }

    @Published var breakKind: BreakKind {
        didSet { defaults.set(breakKind.rawValue, forKey: Key.breakKind) }
    }

    @Published var breakMixIndex: Int {
        didSet { defaults.set(breakMixIndex, forKey: Key.breakMixIndex) }
    }

    @Published var iconFamily: IconFamily {
        didSet { defaults.set(iconFamily.rawValue, forKey: Key.iconFamily) }
    }

    @Published var sitUpChimeEnabled: Bool {
        didSet { defaults.set(sitUpChimeEnabled, forKey: Key.sitUpChimeEnabled) }
    }

    @Published var lookAwayGateEnabled: Bool {
        didSet { defaults.set(lookAwayGateEnabled, forKey: Key.lookAwayGateEnabled) }
    }

    @Published var lookAwayThresholdDegrees: Double {
        didSet {
            let value = Self.clamped(
                lookAwayThresholdDegrees,
                min: LookAway.minThreshold,
                max: LookAway.maxThreshold
            )
            if value != lookAwayThresholdDegrees {
                lookAwayThresholdDegrees = value
                return
            }
            defaults.set(value, forKey: Key.lookAwayThresholdDegrees)
        }
    }

    @Published var showHeadTurnEnabled: Bool {
        didSet { defaults.set(showHeadTurnEnabled, forKey: Key.showHeadTurnEnabled) }
    }

    @Published var hasCompletedWalkthrough: Bool {
        didSet { defaults.set(hasCompletedWalkthrough, forKey: Key.hasCompletedWalkthrough) }
    }

    @Published var isWalkthroughPresented: Bool

    @Published var snoozeEndsAt: Date?

    var isSnoozed: Bool {
        snoozeEndsAt.map { $0 > Date() } ?? false
    }

    private let defaults: UserDefaults
    private var isApplyingAppearance = false

    private enum Key {
        static let warningStyle = "warningStyle"
        static let earlyCueEnabled = "earlyCueEnabled"
        static let cueStartFraction = "cueStartFraction"
        static let overlayFadeInSeconds = "overlayFadeInSeconds"
        static let maxOverlayStrength = "maxOverlayStrength"
        static let overlayTint = "overlayTint"
        static let soundPack = "soundPack"
        static let soundVolume = "soundVolume"
        static let soundAfterDoubleGrace = "soundAfterDoubleGrace"
        static let breakRemindersEnabled = "breakRemindersEnabled"
        static let breakIntervalMinutes = "breakIntervalMinutes"
        static let breakKind = "breakKind"
        static let breakMixIndex = "breakMixIndex"
        static let iconFamily = "iconFamily"
        static let sitUpChimeEnabled = "sitUpChimeEnabled"
        static let lookAwayGateEnabled = "lookAwayGateEnabled"
        static let lookAwayThresholdDegrees = "lookAwayThresholdDegrees"
        static let showHeadTurnEnabled = "showHeadTurnEnabled"
        static let hasCompletedWalkthrough = "hasCompletedWalkthrough"

        static func strength(for style: WarningStyle) -> String {
            "overlayAppearance.\(style.rawValue).strength"
        }

        static func color(for style: WarningStyle) -> String {
            "overlayAppearance.\(style.rawValue).color"
        }
    }

    private enum Cue {
        static let minStartFraction = 0.10
        static let maxStartFraction = 1.00
        static let defaultStartFraction = 0.70
        static let minFadeIn = 0.50
        static let maxFadeIn = 10.00
        static let defaultFadeIn = 3.00
    }

    private enum Strength {
        static let min = 0.05
        static let max = 1.00
        static let fallback = 0.70
        static let blurFallback = 0.05
    }

    private enum Volume {
        static let min = 0.10
        static let max = 0.80
        static let fallback = 0.45
    }

    private enum LookAway {
        static let minThreshold = 20.0
        static let maxThreshold = 60.0
        static let fallbackThreshold = 35.0
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateAppearanceIfNeeded(in: defaults)
        defaults.register(defaults: [
            Key.warningStyle: WarningStyle.glow.rawValue,
            Key.earlyCueEnabled: true,
            Key.cueStartFraction: Cue.defaultStartFraction,
            Key.overlayFadeInSeconds: Cue.defaultFadeIn,
            Key.maxOverlayStrength: Strength.fallback,
            Key.overlayTint: OverlayTint.warm.rawValue,
            Key.soundPack: SoundPack.pop.rawValue,
            Key.soundVolume: Volume.fallback,
            Key.soundAfterDoubleGrace: false,
            Key.breakRemindersEnabled: false,
            Key.breakIntervalMinutes: BreakReminder.defaultIntervalMinutes,
            Key.breakKind: BreakKind.mix.rawValue,
            Key.breakMixIndex: 0,
            Key.iconFamily: IconFamily.postureFigure.rawValue,
            Key.sitUpChimeEnabled: false,
            Key.lookAwayGateEnabled: true,
            Key.lookAwayThresholdDegrees: LookAway.fallbackThreshold,
            Key.showHeadTurnEnabled: true
        ])

        let initialStyle = Self.decode(defaults.string(forKey: Key.warningStyle), fallback: WarningStyle.glow)
        let initialColor = Self.storedColor(for: initialStyle, in: defaults)
        warningStyle = initialStyle
        earlyCueEnabled = defaults.object(forKey: Key.earlyCueEnabled) as? Bool ?? true
        cueStartFraction = Self.finiteClamped(
            defaults.double(forKey: Key.cueStartFraction),
            min: Cue.minStartFraction,
            max: Cue.maxStartFraction,
            fallback: Cue.defaultStartFraction
        )
        overlayFadeInSeconds = Self.finiteClamped(
            defaults.double(forKey: Key.overlayFadeInSeconds),
            min: Cue.minFadeIn,
            max: Cue.maxFadeIn,
            fallback: Cue.defaultFadeIn
        )
        maxOverlayStrength = Self.storedStrength(for: initialStyle, in: defaults)
        overlayColor = initialColor
        overlayTint = OverlayTint(color: initialColor)
            ?? Self.decode(defaults.string(forKey: Key.overlayTint), fallback: .warm)
        soundPack = Self.decode(defaults.string(forKey: Key.soundPack), fallback: .pop)
        soundVolume = Self.clamped(
            defaults.double(forKey: Key.soundVolume),
            min: Volume.min,
            max: Volume.max,
            fallback: Volume.fallback
        )
        soundAfterDoubleGrace = defaults.bool(forKey: Key.soundAfterDoubleGrace)
        breakRemindersEnabled = defaults.bool(forKey: Key.breakRemindersEnabled)
        breakIntervalMinutes = Double(BreakReminder.clampIntervalMinutes(defaults.double(forKey: Key.breakIntervalMinutes)))
        breakKind = Self.decode(defaults.string(forKey: Key.breakKind), fallback: .mix)
        breakMixIndex = defaults.integer(forKey: Key.breakMixIndex)
        iconFamily = Self.decode(defaults.string(forKey: Key.iconFamily), fallback: .postureFigure)
        sitUpChimeEnabled = defaults.bool(forKey: Key.sitUpChimeEnabled)
        lookAwayGateEnabled = defaults.object(forKey: Key.lookAwayGateEnabled) as? Bool ?? true
        lookAwayThresholdDegrees = Self.clamped(
            defaults.double(forKey: Key.lookAwayThresholdDegrees),
            min: LookAway.minThreshold,
            max: LookAway.maxThreshold,
            fallback: LookAway.fallbackThreshold
        )
        showHeadTurnEnabled = defaults.object(forKey: Key.showHeadTurnEnabled) as? Bool ?? true
        hasCompletedWalkthrough = defaults.object(forKey: Key.hasCompletedWalkthrough) as? Bool ?? false
        isWalkthroughPresented = false
    }

    func completeWalkthrough() {
        hasCompletedWalkthrough = true
        isWalkthroughPresented = false
    }

    func startWalkthrough() {
        isWalkthroughPresented = true
    }

    func migrateWalkthroughIfNeeded(hasAnyCalibration: Bool) {
        let hasKey = defaults.object(forKey: Key.hasCompletedWalkthrough) != nil
        guard Walkthrough.shouldMigrateAsCompleted(
            hasCompletionKey: hasKey,
            hasAnyCalibration: hasAnyCalibration
        ) else { return }
        hasCompletedWalkthrough = true
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

    func resetOverlayAppearance() {
        guard warningStyle != .off else { return }
        isApplyingAppearance = true
        maxOverlayStrength = Self.defaultStrength(for: warningStyle)
        overlayColor = .warm
        overlayTint = .warm
        isApplyingAppearance = false
        defaults.set(maxOverlayStrength, forKey: Key.strength(for: warningStyle))
        persist(color: overlayColor, for: warningStyle)
        defaults.set(maxOverlayStrength, forKey: Key.maxOverlayStrength)
        defaults.set(overlayTint.rawValue, forKey: Key.overlayTint)
    }

    private func loadAppearance(for style: WarningStyle) {
        guard style != .off else { return }
        isApplyingAppearance = true
        maxOverlayStrength = Self.storedStrength(for: style, in: defaults)
        overlayColor = Self.storedColor(for: style, in: defaults)
        overlayTint = OverlayTint(color: overlayColor) ?? overlayTint
        isApplyingAppearance = false
    }

    private func persist(color: OverlayColor, for style: WarningStyle) {
        guard let data = try? JSONEncoder().encode(color) else { return }
        defaults.set(data, forKey: Key.color(for: style))
    }

    private static func migrateAppearanceIfNeeded(in defaults: UserDefaults) {
        let legacyStrength: Double
        if let stored = defaults.object(forKey: Key.maxOverlayStrength) as? NSNumber {
            legacyStrength = finiteClamped(
                stored.doubleValue,
                min: Strength.min,
                max: Strength.max,
                fallback: Strength.fallback
            )
        } else {
            legacyStrength = Strength.fallback
        }
        let legacyTint = decode(defaults.string(forKey: Key.overlayTint), fallback: OverlayTint.warm)
        let legacyColor = legacyTint.color

        for style in WarningStyle.allCases where style != .off {
            let strengthKey = Key.strength(for: style)
            if defaults.object(forKey: strengthKey) == nil {
                defaults.set(style == .blur ? Strength.blurFallback : legacyStrength, forKey: strengthKey)
            }

            let colorKey = Key.color(for: style)
            if defaults.object(forKey: colorKey) == nil,
               let data = try? JSONEncoder().encode(legacyColor) {
                defaults.set(data, forKey: colorKey)
            }
        }
    }

    private static func storedStrength(for style: WarningStyle, in defaults: UserDefaults) -> Double {
        guard style != .off else { return Strength.fallback }
        return finiteClamped(
            defaults.double(forKey: Key.strength(for: style)),
            min: Strength.min,
            max: Strength.max,
            fallback: defaultStrength(for: style)
        )
    }

    private static func storedColor(for style: WarningStyle, in defaults: UserDefaults) -> OverlayColor {
        guard style != .off,
              let data = defaults.data(forKey: Key.color(for: style)),
              let color = try? JSONDecoder().decode(OverlayColor.self, from: data) else {
            return .warm
        }
        return color
    }

    private static func defaultStrength(for style: WarningStyle) -> Double {
        style == .blur ? Strength.blurFallback : Strength.fallback
    }

    private static func decode<T: RawRepresentable>(_ raw: String?, fallback: T) -> T where T.RawValue == String {
        raw.flatMap(T.init(rawValue:)) ?? fallback
    }

    private static func clamped(_ value: Double, min: Double, max: Double, fallback: Double = 0) -> Double {
        if value == 0 { return fallback == 0 ? min : fallback }
        return Swift.min(Swift.max(value, min), max)
    }

    private static func finiteClamped(
        _ value: Double,
        min: Double,
        max: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, min), max)
    }
}

private extension OverlayTint {
    init?(color: OverlayColor) {
        switch color {
        case .warm: self = .warm
        case .cool: self = .cool
        case .alert: self = .alert
        default: return nil
        }
    }

    var color: OverlayColor {
        switch self {
        case .warm: .warm
        case .cool: .cool
        case .alert: .alert
        }
    }
}
