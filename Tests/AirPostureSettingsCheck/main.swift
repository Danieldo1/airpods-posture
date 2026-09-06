import Foundation

private var failures = 0

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual != expected {
        FileHandle.standardError.write(Data("FAIL \(name): expected \(expected), got \(actual)\n".utf8))
        failures += 1
    }
}

@MainActor
private func withDefaults(_ body: (UserDefaults) -> Void) {
    let suite = "AirPostureSettingsCheck.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults)
}

@MainActor
private func checkFreshDefaultsAndReset() {
    withDefaults { defaults in
        let settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings.earlyCueEnabled, true, "early cue defaults on")
        expectEqual(settings.cueStartFraction, 0.70, "cue onset default")
        expectEqual(settings.overlayFadeInSeconds, 3, "fade-in default")
        expectEqual(settings.maxOverlayStrength, 0.70, "non-blur strength default")
        expectEqual(settings.overlayColor, .warm, "fresh color default")

        settings.warningStyle = .blur
        expectEqual(settings.maxOverlayStrength, 0.05, "blur strength default")
        settings.maxOverlayStrength = 0.8
        settings.overlayColor = OverlayColor(red: 0.2, green: 0.3, blue: 0.4)
        settings.resetOverlayAppearance()
        expectEqual(settings.maxOverlayStrength, 0.05, "blur reset strength")
        expectEqual(settings.overlayColor, .warm, "blur reset color")
    }
}

@MainActor
private func checkPerStyleRoundTrip() {
    withDefaults { defaults in
        var settings: AirPostureSettings? = AirPostureSettings(defaults: defaults)
        settings?.maxOverlayStrength = 0.31
        settings?.overlayColor = OverlayColor(red: 0.11, green: 0.22, blue: 0.33)

        settings?.warningStyle = .border
        settings?.maxOverlayStrength = 0.82
        settings?.overlayColor = OverlayColor(red: 0.44, green: 0.55, blue: 0.66)

        settings?.warningStyle = .dim
        settings?.maxOverlayStrength = 0.63
        settings?.overlayColor = OverlayColor(red: 0.12, green: 0.34, blue: 0.56)

        settings?.warningStyle = .blur
        settings?.maxOverlayStrength = 0.17
        settings?.overlayColor = OverlayColor(red: 0.65, green: 0.43, blue: 0.21)

        settings?.warningStyle = .glow
        expectEqual(settings?.maxOverlayStrength, 0.31, "glow strength restored after switching")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.11, green: 0.22, blue: 0.33),
            "glow color restored after switching"
        )

        settings?.warningStyle = .off
        settings?.maxOverlayStrength = 0.99
        settings?.overlayColor = .alert
        settings?.warningStyle = .glow
        expectEqual(settings?.maxOverlayStrength, 0.31, "Off does not overwrite glow strength")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.11, green: 0.22, blue: 0.33),
            "Off does not overwrite glow color"
        )

        settings?.resetOverlayAppearance()
        expectEqual(settings?.maxOverlayStrength, 0.70, "non-blur reset strength")
        expectEqual(settings?.overlayColor, .warm, "non-blur reset color")
        settings?.maxOverlayStrength = 0.31
        settings?.overlayColor = OverlayColor(red: 0.11, green: 0.22, blue: 0.33)

        settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.maxOverlayStrength, 0.31, "glow strength restored after reload")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.11, green: 0.22, blue: 0.33),
            "glow color restored after reload"
        )
        settings?.warningStyle = .border
        expectEqual(settings?.maxOverlayStrength, 0.82, "border strength restored after reload")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.44, green: 0.55, blue: 0.66),
            "border color restored after reload"
        )
        settings?.warningStyle = .dim
        expectEqual(settings?.maxOverlayStrength, 0.63, "Dim strength restored after reload")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.12, green: 0.34, blue: 0.56),
            "Dim color restored after reload"
        )
        settings?.warningStyle = .blur
        expectEqual(settings?.maxOverlayStrength, 0.17, "Blur strength restored after reload")
        expectEqual(
            settings?.overlayColor,
            OverlayColor(red: 0.65, green: 0.43, blue: 0.21),
            "Blur color restored after reload"
        )
    }
}

@MainActor
private func checkOneTimeLegacyMigration() {
    withDefaults { defaults in
        defaults.set(0.42, forKey: "maxOverlayStrength")
        defaults.set(OverlayTint.cool.rawValue, forKey: "overlayTint")

        var settings: AirPostureSettings? = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.maxOverlayStrength, 0.42, "legacy strength migrated to glow")
        expectEqual(settings?.overlayColor, .cool, "legacy tint migrated to glow")

        settings?.warningStyle = .dim
        expectEqual(settings?.maxOverlayStrength, 0.42, "legacy strength migrated to dim")
        expectEqual(settings?.overlayColor, .cool, "legacy tint migrated to dim")

        settings?.warningStyle = .blur
        expectEqual(settings?.maxOverlayStrength, 0.05, "legacy strength excluded from blur")
        expectEqual(settings?.overlayColor, .cool, "legacy tint migrated to blur")

        defaults.set(0.91, forKey: "maxOverlayStrength")
        defaults.set(OverlayTint.alert.rawValue, forKey: "overlayTint")
        settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.maxOverlayStrength, 0.05, "blur migration is not repeated")
        expectEqual(settings?.overlayColor, .cool, "blur color migration is not repeated")
        settings?.warningStyle = .glow
        expectEqual(settings?.maxOverlayStrength, 0.42, "glow migration is not repeated")
        expectEqual(settings?.overlayColor, .cool, "glow color migration is not repeated")
    }
}

@MainActor
private func checkValidationAndPersistence() {
    withDefaults { defaults in
        var settings: AirPostureSettings? = AirPostureSettings(defaults: defaults)
        settings?.cueStartFraction = .nan
        settings?.overlayFadeInSeconds = .infinity
        settings?.maxOverlayStrength = .nan
        expectEqual(settings?.cueStartFraction, 0.70, "non-finite onset falls back")
        expectEqual(settings?.overlayFadeInSeconds, 3, "non-finite fade-in falls back")
        expectEqual(settings?.maxOverlayStrength, 0.70, "non-finite strength falls back")

        settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.cueStartFraction, 0.70, "non-finite onset fallback persists")
        expectEqual(settings?.overlayFadeInSeconds, 3, "non-finite fade-in fallback persists")
        expectEqual(settings?.maxOverlayStrength, 0.70, "non-finite strength fallback persists")

        settings?.cueStartFraction = 2
        settings?.overlayFadeInSeconds = 0.1
        settings?.maxOverlayStrength = 0
        expectEqual(settings?.cueStartFraction, 1, "onset clamps to one")
        expectEqual(settings?.overlayFadeInSeconds, 0.5, "fade-in clamps to half second")
        expectEqual(settings?.maxOverlayStrength, 0.05, "strength clamps to five percent")

        settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.cueStartFraction, 1, "validated onset persists")
        expectEqual(settings?.overlayFadeInSeconds, 0.5, "validated fade-in persists")
        expectEqual(settings?.maxOverlayStrength, 0.05, "validated minimum strength persists")

        settings?.maxOverlayStrength = 2
        expectEqual(settings?.maxOverlayStrength, 1, "strength clamps to one")
        settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings?.maxOverlayStrength, 1, "validated strength persists")
    }
}

@MainActor
private func checkInvalidStoredColorFallback() {
    withDefaults { defaults in
        let invalid = Data(#"{"red":2,"green":0.2,"blue":0.3}"#.utf8)
        defaults.set(invalid, forKey: "overlayAppearance.glow.color")
        let settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings.overlayColor, .warm, "invalid stored color falls back to Warm")
    }
}

@MainActor
private func checkBreakReminderDefaultsAndClamp() {
    withDefaults { defaults in
        let settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings.breakRemindersEnabled, false, "break reminders default off")
        expectEqual(settings.breakIntervalMinutes, 45, "break interval default")
        expectEqual(settings.breakKind, .mix, "break kind default mix")
        expectEqual(settings.breakMixIndex, 0, "mix index default")

        settings.breakIntervalMinutes = 47
        expectEqual(settings.breakIntervalMinutes, 45, "47 clamps to 45")
        settings.breakIntervalMinutes = 48
        expectEqual(settings.breakIntervalMinutes, 50, "48 clamps to 50")
        settings.breakIntervalMinutes = .infinity
        expectEqual(settings.breakIntervalMinutes, 45, "non-finite interval falls back")

        settings.breakKind = .walk
        settings.breakRemindersEnabled = true
        settings.breakMixIndex = 2

        let reloaded = AirPostureSettings(defaults: defaults)
        expectEqual(reloaded.breakRemindersEnabled, true, "enabled persists")
        expectEqual(reloaded.breakIntervalMinutes, 45, "fallback persist after non-finite")
        expectEqual(reloaded.breakKind, .walk, "kind persists")
        expectEqual(reloaded.breakMixIndex, 2, "mix index persists")
    }

    withDefaults { defaults in
        defaults.set("nope", forKey: "breakKind")
        let settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings.breakKind, .mix, "invalid kind falls back to mix")
    }
}

@main
private struct AirPostureSettingsCheck {
    @MainActor
    static func main() {
        checkBreakReminderDefaultsAndClamp()
        checkFreshDefaultsAndReset()
        checkPerStyleRoundTrip()
        checkOneTimeLegacyMigration()
        checkValidationAndPersistence()
        checkInvalidStoredColorFallback()

        if failures > 0 {
            FileHandle.standardError.write(Data("\(failures) settings check(s) failed\n".utf8))
            exit(1)
        }
        print("AirPosture settings checks passed")
    }
}
