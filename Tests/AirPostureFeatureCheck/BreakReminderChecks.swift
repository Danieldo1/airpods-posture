import AirPostureCore
import Foundation

func expectTrue(_ condition: Bool, _ name: String) {
    if !condition {
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
        failures += 1
    }
}

func expectValue<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual != expected {
        FileHandle.standardError.write(Data("FAIL \(name): expected \(expected), got \(actual)\n".utf8))
        failures += 1
    }
}

func runBreakReminderChecks() {
    expectValue(BreakReminder.clampIntervalMinutes(.nan), 45, "non-finite interval falls back")
    expectValue(BreakReminder.clampIntervalMinutes(4.9), 5, "rounds then clamps to minimum")
    expectValue(BreakReminder.clampIntervalMinutes(47), 45, "47 rounds to 45")
    expectValue(BreakReminder.clampIntervalMinutes(48), 50, "48 rounds to 50")
    expectValue(BreakReminder.clampIntervalMinutes(200), 120, "clamps to maximum")
    expectValue(BreakReminder.clampIntervalMinutes(-200), 5, "clamps negative interval")
    expectValue(BreakReminder.clampIntervalMinutes(.infinity), 45, "infinite interval falls back")
    expectValue(BreakReminder.clampIntervalMinutes(.greatestFiniteMagnitude), 120, "huge finite interval clamps without overflow")

    let now = Date(timeIntervalSince1970: 1_000_000)
    let fire = BreakReminder.nextFireDate(now: now, intervalMinutes: 45)
    expectValue(fire.timeIntervalSince(now), 2700, "45 minutes is 2700 seconds")
    expectValue(BreakReminder.remainingSeconds(now: now, nextFire: fire), 2700, "full interval remaining")
    expectValue(BreakReminder.remainingSeconds(now: fire.addingTimeInterval(-0.2), nextFire: fire), 1, "sub-second remaining rounds up")
    expectTrue(BreakReminder.isDue(now: fire, nextFire: fire), "due at boundary")
    expectTrue(!BreakReminder.isDue(now: now, nextFire: fire), "not due before boundary")
    expectValue(BreakReminder.remainingSeconds(now: fire.addingTimeInterval(90), nextFire: fire), 0, "overdue remaining is zero")

    expectValue(BreakReminder.resolvedKind(.walk, mixIndex: 99), .walk, "fixed kind ignores mix index")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: 0), .walk, "mix 0 is walk")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: 1), .water, "mix 1 is water")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: 2), .eyes, "mix 2 is eyes")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: 3), .walk, "mix wraps")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: -1), .eyes, "negative mix wraps to eyes")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: Int.max), .water, "maximum mix index resolves")
    expectValue(BreakReminder.resolvedKind(.mix, mixIndex: Int.min), .water, "minimum mix index resolves")
    expectValue(BreakReminder.nextMixIndex(2), 3, "mix index advances")
    expectValue(BreakReminder.nextMixIndex(Int.max), Int.min, "mix increment does not overflow")

    expectValue(
        BreakReminder.banner(kind: .walk, mixIndex: 0),
        BreakBanner(title: "Time for a walk", body: "Stand up and take a short walk away from the screen."),
        "walk copy"
    )
    expectValue(
        BreakReminder.banner(kind: .water, mixIndex: 0),
        BreakBanner(title: "Drink some water", body: "Take a sip and look away from the screen for a moment."),
        "water copy"
    )
    expectValue(
        BreakReminder.banner(kind: .eyes, mixIndex: 0),
        BreakBanner(title: "Rest your eyes", body: "Look away from the screen for 20 seconds."),
        "eyes copy"
    )
    expectValue(
        BreakReminder.banner(kind: .mix, mixIndex: 2),
        BreakReminder.banner(kind: .eyes, mixIndex: 0),
        "mix banner uses resolved kind"
    )

    expectValue(BreakReminder.statusItemText(remainingSeconds: 3905), "1h 05m", "status hour form")
    expectValue(BreakReminder.statusItemText(remainingSeconds: 3600), "1h 00m", "status exact hour")
    expectValue(BreakReminder.statusItemText(remainingSeconds: 1440), "24m", "status minutes")
    expectValue(BreakReminder.statusItemText(remainingSeconds: 59), "0:59", "status seconds")
    expectValue(BreakReminder.statusItemText(remainingSeconds: 0), "0:00", "status zero")

    expectValue(BreakReminder.popoverText(remainingSeconds: 3905), "1:05:05", "popover hour form")
    expectValue(BreakReminder.popoverText(remainingSeconds: 1458), "24:18", "popover minutes")
    expectValue(BreakReminder.popoverText(remainingSeconds: 5), "0:05", "popover under a minute")

    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 3905), "1 hour 5 minutes", "a11y hour")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 7200), "2 hours 0 minutes", "a11y two hours")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 1440), "24 minutes", "a11y minutes")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 60), "1 minute", "a11y one minute")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 3660), "1 hour 1 minute", "a11y singular hour and minute")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 1), "1 second", "a11y one second")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 0), "0 seconds", "a11y zero")
}
