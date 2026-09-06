# Break Reminders Implementation Plan

> **For Codex / agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work and review uncommitted diffs. Do **not** commit, branch, or start a long-lived process unless the operator explicitly asks.

**Goal:** Add an opt-in repeating break clock that shows a countdown in the menu-bar extra and popover, then plays the selected sound and a walk / water / eyes banner — never a slouch overlay.

**Architecture:** Put deterministic interval, copy, mix rotation, and countdown formatting in `AirPostureCore.BreakReminder`. Persist on/off, minutes, kind, and mix index on `AirPostureSettings`. Drive the live countdown from a dedicated `BreakReminderClock`. Fire through `AlertService.remindBreakIfAllowed` using notification id `airposture.break`. Do not touch pose scoring, overlays, Coolio, or weekly analytics.

**Tech Stack:** Swift 5.9 / macOS 14+, SwiftUI `MenuBarExtra` `.window`, AppKit, Combine, UserNotifications, existing executable-check harness (no XCTest).

## Codex operator prompt

Paste this as the Codex task. This plan file is the source of truth.

```xml
<task>
Implement docs/superpowers/plans/2026-09-06-break-reminders.md in /Users/Daniel_1/Desktop/mac-posture.
Add an opt-in repeating break reminder: user-set interval, Walk / Water / Eyes / Mix, countdown in the menu-bar extra and popover, banner + selected sound only.
Follow the plan task-by-task. Do not invent a different architecture.
</task>

<completeness_contract>
Finish every task: core model + feature checks, settings persistence, AlertService break path, BreakReminderClock, menu-bar + popover UI, pbxproj, native-check script, README.
Do not stop after the core types. The countdown must be visible in the MenuBarExtra label when the feature is on.
</completeness_contract>

<default_follow_through_policy>
Keep going. Prefer the plan’s types, names, copy, and file paths over improvisation.
Only stop if a required production API is missing and cannot be inferred from the plan or existing AlertService / settings code.
</default_follow_through_policy>

<verification_loop>
After implementation, run the exact commands in the plan’s verification section.
Do not claim the banner or sound is audible from a compile alone. Report which checks passed and which native QA still needs a human.
</verification_loop>

<action_safety>
No commits, no branches, no force-git, no package-manager upgrades.
Do not change slouch ellipse math, grace, overlay rendering, Coolio / SceneKit, or weekly analytics accumulation.
Do not reuse notification id airposture.slouch for breaks.
Do not make Focus skip slouch sound — only the new break path is fully silenced by Focus.
Do not revert unrelated uncommitted files (including .gitignore).
</action_safety>
```

## Locked product decisions

These are already decided. Do not reopen them.

| Decision | Value |
|---|---|
| Default | Off |
| Interval | User-set, 5–120 minutes, 5-minute steps, default 45 |
| Schedule | Repeating wall-clock interval while the app is running, even if AirPods are disconnected |
| Fire surface | Selected sound pack + notification banner. **No overlay, no Coolio prompt, no popover auto-open** |
| Kind | Walk / Water / Eyes / Mix (Mix rotates Walk → Water → Eyes) |
| Quiet | Existing snooze **or** authorized Focus: no break sound and no break banner. Timer keeps running. No backlog |
| Sleep / missed fire | Skip the missed fire, start a fresh interval from now |
| Launch / enable / interval change | Start a full new interval. Do not persist leftover seconds |
| Countdown | Menu-bar extra text **and** popover row when the feature is on |
| Slouch path | Unchanged, including 45s throttle and Focus-skips-banner-only |

### Banner copy (exact)

| Resolved kind | Title | Body |
|---|---|---|
| Walk | Time for a walk | Stand up and take a short walk away from the screen. |
| Water | Drink some water | Take a sip and look away from the screen for a moment. |
| Eyes | Rest your eyes | Look away from the screen for 20 seconds. |

Mix resolves to one of those three. It never uses the word Mix on the banner.

### Countdown text (exact)

`remaining` is a non-negative `Int` second count.

**Menu bar (`statusItemText`):**

- `remaining >= 3600` → `1h 05m` (`hours` + space + zero-padded minutes + `m`)
- `remaining >= 60` → `24m`
- else → `0:45` (always `0:` plus two-digit seconds, including `0:00`)

**Popover (`popoverText`):**

- `remaining >= 3600` → `1:05:07` (hours + `:` + zero-padded minutes + `:` + zero-padded seconds)
- else → `24:18` (minutes, no padding, + `:` + zero-padded seconds)

**VoiceOver remaining (`accessibilityRemaining`):**

- `>= 3600` → `1 hour 5 minutes` / `2 hours 0 minutes`
- `>= 60` → `24 minutes`
- `1` → `1 second`
- else → `N seconds`

---

## Global Constraints

- Work on the current checkout. Do not create a branch, commit, or start a dev server.
- Preserve unrelated uncommitted files.
- macOS 14+ (`Package.swift` platforms). No new dependencies.
- Installed Command Line Tools have no XCTest. Use `expectEqual` / `check` helpers and `exit(1)`.
- Native compile uses a temp module cache. Prefer `make test`. Fallback: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`.
- `AirPostureFeatureCheck` can import `AirPostureCore` only. Settings / AlertService tests stay in `Tests/run-native-checks.sh`.
- `AirPostureSettings` is compiled into native checks **without** the AirPostureCore module. If it references `BreakKind`, `Tests/run-native-checks.sh` must also compile `Sources/AirPostureCore/BreakReminder.swift`.
- Xcode target lists files explicitly in `AirPostureMac.xcodeproj/project.pbxproj`. New Swift files need `A1…` build-file IDs and `A2…` file-ref IDs.

---

## File structure

- Create: `Sources/AirPostureCore/BreakReminder.swift` — kinds, clamp, schedule, mix, copy, countdown strings.
- Create: `Tests/AirPostureFeatureCheck/BreakReminderChecks.swift` — core assertions.
- Create: `Sources/AirPostureMac/BreakReminderClock.swift` — 1 Hz timer, next-fire date, suppression, AlertService call.
- Modify: `Tests/AirPostureFeatureCheck/main.swift` — register group `breaks`.
- Modify: `Sources/AirPostureMac/AirPostureSettings.swift` — persist the four break preferences.
- Modify: `Tests/AirPostureSettingsCheck/main.swift` — defaults, clamp, persistence.
- Modify: `Sources/AirPostureMac/AlertService.swift` — `remindBreakIfAllowed`.
- Modify: `Tests/AirPostureSoundCheck/main.swift` — break vs slouch policy.
- Modify: `Sources/AirPostureMac/AirPostureMacApp.swift` — own the clock; put countdown in the `MenuBarExtra` label.
- Modify: `Sources/AirPostureMac/MenuBarView.swift` — visible countdown row + Breaks options.
- Modify: `Sources/AirPostureMac/MenuBarIcon.swift` — VoiceOver includes remaining time when enabled.
- Modify: `Tests/run-native-checks.sh` — compile `BreakReminder.swift` with settings / sound / store checks.
- Modify: `AirPostureMac.xcodeproj/project.pbxproj` — add both new Swift files.
- Modify: `README.md` — console + customization rows.
- Do **not** modify overlay, tracker scoring, bust, or analytics files except if a compile requires an unused import (it should not).

---

### Task 1: Core break model

**Files:**
- Create: `Sources/AirPostureCore/BreakReminder.swift`
- Create: `Tests/AirPostureFeatureCheck/BreakReminderChecks.swift`
- Modify: `Tests/AirPostureFeatureCheck/main.swift`

**Interfaces:**

```swift
public enum BreakKind: String, CaseIterable, Identifiable, Sendable {
    case walk, water, eyes, mix
    public var id: String { rawValue }
    public var title: String // "Walk", "Water", "Eyes", "Mix"
}

public struct BreakBanner: Equatable, Sendable {
    public let title: String
    public let body: String
}

public enum BreakReminder {
    public static let minIntervalMinutes = 5
    public static let maxIntervalMinutes = 120
    public static let defaultIntervalMinutes = 45
    public static let intervalStepMinutes = 5

    public static func clampIntervalMinutes(_ value: Double) -> Int
    public static func nextFireDate(now: Date, intervalMinutes: Int) -> Date
    public static func remainingSeconds(now: Date, nextFire: Date) -> Int
    public static func isDue(now: Date, nextFire: Date) -> Bool
    public static func resolvedKind(_ kind: BreakKind, mixIndex: Int) -> BreakKind // never .mix
    public static func nextMixIndex(_ mixIndex: Int) -> Int
    public static func banner(kind: BreakKind, mixIndex: Int) -> BreakBanner
    public static func statusItemText(remainingSeconds: Int) -> String
    public static func popoverText(remainingSeconds: Int) -> String
    public static func accessibilityRemaining(remainingSeconds: Int) -> String
}
```

`clampIntervalMinutes`: if `value` is not finite, return 45. Otherwise round to the nearest 5, then clamp to 5...120.

`nextFireDate`: `now + TimeInterval(clampIntervalMinutes(Double(intervalMinutes)) * 60)`.

`remainingSeconds`: `max(0, Int(ceil(nextFire.timeIntervalSince(now))))`.

`isDue`: `now >= nextFire`.

`resolvedKind`: Walk / Water / Eyes return themselves. Mix uses `mixIndex` modulo 3 in that order (0 walk, 1 water, 2 eyes). Negative or huge indexes still modulo 3 in the non-negative residue (`((mixIndex % 3) + 3) % 3`).

`nextMixIndex`: `mixIndex &+ 1` is fine; consumers persist the increment. Tests may use `mixIndex + 1`.

`banner(kind:mixIndex:)` always uses `resolvedKind`.

- [ ] **Step 1: Write the failing feature checks**

Create `Tests/AirPostureFeatureCheck/BreakReminderChecks.swift` with the same `expectEqual` helpers already in `main.swift` (do not duplicate the helpers; use the file-level functions from `main.swift`, or put local `expectEqual` overloads for `String` / `Int` / `BreakKind` / `Bool` in the new file if the existing helpers are `Double`-only).

`main.swift` currently only has `expectEqual` for `Double`. Add these helpers in `BreakReminderChecks.swift`:

```swift
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
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 1), "1 second", "a11y one second")
    expectValue(BreakReminder.accessibilityRemaining(remainingSeconds: 0), "0 seconds", "a11y zero")
}
```

In `Tests/AirPostureFeatureCheck/main.swift`, add `"breaks"` to the default groups and the switch:

```swift
    case "breaks":
        runBreakReminderChecks()
```

Default groups become `["warnings", "analytics", "breaks"]`.

- [ ] **Step 2: Run the check and confirm it fails because `BreakReminder` is missing**

```bash
mkdir -p "${TMPDIR:-/tmp}/airposture-make/clang-module-cache"
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/airposture-make/clang-module-cache" \
  swift run --disable-sandbox \
  --cache-path "${TMPDIR:-/tmp}/airposture-make/cache" \
  --config-path "${TMPDIR:-/tmp}/airposture-make/config" \
  --security-path "${TMPDIR:-/tmp}/airposture-make/security" \
  AirPostureFeatureCheck breaks
```

Expected: compile failure (`BreakReminder` not found) or FAIL lines.

- [ ] **Step 3: Implement `Sources/AirPostureCore/BreakReminder.swift`**

Public API exactly as in **Interfaces**. `BreakBanner` must be `Equatable`. Format hours/minutes/seconds with integer division; do not use `DateComponentsFormatter` (it localizes and will fail the exact strings).

Zero-pad with `String(format: "%02d", value)`.

- [ ] **Step 4: Re-run the breaks group and confirm it passes**

Same command as Step 2.

Expected: `AirPosture feature checks passed: breaks`

- [ ] **Step 5: Do not commit**

Leave the files uncommitted.

---

### Task 2: Settings persistence

**Files:**
- Modify: `Sources/AirPostureMac/AirPostureSettings.swift`
- Modify: `Tests/AirPostureSettingsCheck/main.swift`
- Modify: `Tests/run-native-checks.sh`

**Interfaces:**

On `AirPostureSettings`:

```swift
@Published var breakRemindersEnabled: Bool
@Published var breakIntervalMinutes: Double
@Published var breakKind: BreakKind
@Published var breakMixIndex: Int
```

Keys: `breakRemindersEnabled`, `breakIntervalMinutes`, `breakKind`, `breakMixIndex`.

Registered defaults: `false`, `45`, `"mix"`, `0`.

`breakIntervalMinutes` didSet: write `BreakReminder.clampIntervalMinutes` as `Double`. If the incoming value is already the clamped `Double`, persist it; if you must reassign the property to the clamped value, guard against recursion the same way `lookAwayThresholdDegrees` already does.

`breakKind` unknown stored raw value → `.mix`.

`breakMixIndex` non-finite is impossible for `Int`; persist whatever integer is set. The core resolver wraps it.

- [ ] **Step 1: Add failing settings checks** at the end of `Tests/AirPostureSettingsCheck/main.swift` (before `main()` calls) and call them from `main()`:

```swift
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
```

`expectEqual` in this file is generic `Equatable`, so `BreakKind` works once the type compiles.

- [ ] **Step 2: Compile the settings check and confirm it fails**

`Tests/run-native-checks.sh` currently compiles only `WarningIntensity.swift` + `AirPostureSettings.swift`. Update `SETTINGS_SOURCES` **first** so the new type can compile:

```bash
SETTINGS_SOURCES=(
  Sources/AirPostureCore/WarningIntensity.swift
  Sources/AirPostureCore/BreakReminder.swift
  Sources/AirPostureMac/AirPostureSettings.swift
)
```

Then run:

```bash
Tests/run-native-checks.sh
```

Expected before settings properties exist: compile failure (`breakRemindersEnabled` not found).

- [ ] **Step 3: Add the four properties to `AirPostureSettings`**

Follow the existing `@Published` + `Key` + `defaults.register` + init load pattern. Do not migrate anything else.

- [ ] **Step 4: Re-run `Tests/run-native-checks.sh`**

Expected: settings checks pass. Sound and store checks must still pass (they inherit `SETTINGS_SOURCES`).

- [ ] **Step 5: Do not commit**

---

### Task 3: Break fire path on AlertService

**Files:**
- Modify: `Sources/AirPostureMac/AlertService.swift`
- Modify: `Tests/AirPostureSoundCheck/main.swift`

**Interfaces:**

```swift
func remindBreakIfAllowed(banner: BreakBanner)
```

Behavior:

1. If `settings` is missing or `settings.isSnoozed` → return. No sound, no banner, do **not** write `lastAlertAt`.
2. If `shouldSkipBanner()` is true (authorized Focus in production; injected flag in tests) → return. No sound, no banner, do **not** write `lastAlertAt`. This is **different** from slouch, which still plays sound under Focus.
3. Play the warning channel with `settings.soundPack` and `settings.soundVolume` (same helper as slouch).
4. Post a notification with `banner.title` / `banner.body`, `sound = nil`, identifier **`airposture.break`**.
5. Never assign `lastAlertAt`. A break must not start or consume the 45-second slouch cooldown.

Production poster:

```swift
let content = UNMutableNotificationContent()
content.title = banner.title
content.body = banner.body
content.sound = nil
UNUserNotificationCenter.current().add(
    UNNotificationRequest(identifier: "airposture.break", content: content, trigger: nil),
    withCompletionHandler: nil
)
```

Test initializer today is `postNotification: () -> Void`. Change it to:

```swift
init(
    playback: any SoundPlaybackServing,
    now: @escaping () -> Date,
    shouldSkipBanner: @escaping () -> Bool,
    postNotification: @escaping (_ identifier: String) -> Void
)
```

Production `postSitUpNotification` calls `notificationPoster?("airposture.slouch")` when injected, else posts slouch as today.

`remindBreakIfAllowed` calls `notificationPoster?("airposture.break")` when injected, else posts the break request.

Update the existing sound-check closure from `{ bannerCount += 1 }` to `{ _ in bannerCount += 1 }` so slouch tests keep passing.

- [ ] **Step 1: Add `checkBreakReminderPolicy()` to `Tests/AirPostureSoundCheck/main.swift` and call it from `main()`**

```swift
@MainActor
private func checkBreakReminderPolicy() {
    let (defaults, suite) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AirPostureSettings(defaults: defaults)
    settings.soundPack = .bottle
    settings.soundVolume = 0.4
    let playback = PlaybackSpy()
    var skipBanner = false
    var identifiers: [String] = []
    let service = AlertService(
        playback: playback,
        now: Date.init,
        shouldSkipBanner: { skipBanner },
        postNotification: { identifiers.append($0) }
    )
    service.configure(settings: settings)

    let banner = BreakBanner(title: "Drink some water", body: "Take a sip and look away from the screen for a moment.")

    settings.snooze(minutes: 5)
    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.isEmpty && identifiers.isEmpty, "snooze suppresses break sound and banner")

    settings.clearSnooze()
    skipBanner = true
    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.isEmpty && identifiers.isEmpty, "Focus suppresses break sound and banner")

    skipBanner = false
    service.nudgeIfAllowed(slouchElapsedSeconds: 5, gracePeriodSeconds: 5)
    check(identifiers == ["airposture.slouch"], "slouch still uses slouch identifier")
    let slouchRequests = playback.requests.count

    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.last == .init(pack: .bottle, volume: 0.4, channel: .warning), "break uses selected warning sound")
    check(identifiers == ["airposture.slouch", "airposture.break"], "break uses break identifier")

    service.remindBreakIfAllowed(banner: banner)
    check(playback.requests.count == slouchRequests + 2, "break is not throttled by slouch cooldown")
    check(identifiers == ["airposture.slouch", "airposture.break", "airposture.break"], "second break still posts")
}
```

- [ ] **Step 2: Compile `Tests/run-native-checks.sh` and confirm the new test fails** (missing method or wrong initializer).

- [ ] **Step 3: Implement `remindBreakIfAllowed` and the identifier-taking poster.** Keep `nudgeIfAllowed` Focus behavior: sound plays, banner skipped.

- [ ] **Step 4: Re-run `Tests/run-native-checks.sh`.** Expected: sound checks passed, including the new function.

- [ ] **Step 5: Do not commit**

---

### Task 4: `BreakReminderClock`

**Files:**
- Create: `Sources/AirPostureMac/BreakReminderClock.swift`
- Modify: `Sources/AirPostureMac/AirPostureMacApp.swift`

**Interfaces:**

```swift
@MainActor
final class BreakReminderClock: ObservableObject {
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isEnabled: Bool

    var statusItemText: String { BreakReminder.statusItemText(remainingSeconds: remainingSeconds) }
    var popoverText: String { BreakReminder.popoverText(remainingSeconds: remainingSeconds) }
    var accessibilityRemaining: String { BreakReminder.accessibilityRemaining(remainingSeconds: remainingSeconds) }

    init(
        settings: AirPostureSettings,
        alerts: AlertService,
        now: @escaping () -> Date = Date.init,
        isFocusSuppressing: @escaping () -> Bool = {
            let center = INFocusStatusCenter.default
            guard center.authorizationStatus == .authorized else { return false }
            return center.focusStatus.isFocused == true
        }
    )

    func evaluate(now: Date? = nil) // public for tests / wake
}
```

Rules inside `evaluate`:

- If `!settings.breakRemindersEnabled`: `isEnabled = false`, `remainingSeconds = 0`, `nextFire = nil`, return. Do not fire.
- `isEnabled = true`.
- If `nextFire == nil` **or** `settings.breakIntervalMinutes` / enabled just changed (see below): `nextFire = BreakReminder.nextFireDate(now: now, intervalMinutes: Int(settings.breakIntervalMinutes))`.
- If `BreakReminder.isDue(now: now, nextFire: nextFire)`:
  - `let suppressed = settings.isSnoozed || isFocusSuppressing()`
  - if `!suppressed`: `alerts.remindBreakIfAllowed(banner: BreakReminder.banner(kind: settings.breakKind, mixIndex: settings.breakMixIndex))`
  - always: `settings.breakMixIndex = BreakReminder.nextMixIndex(settings.breakMixIndex)`
  - always: `nextFire = BreakReminder.nextFireDate(now: now, intervalMinutes: Int(settings.breakIntervalMinutes))` (fresh interval from **now**, never catch-up)
- `remainingSeconds = BreakReminder.remainingSeconds(now: now, nextFire: nextFire!)`

Restart the interval when:

- `breakRemindersEnabled` flips to true
- `breakIntervalMinutes` changes while enabled

Implement by storing `private var scheduledIntervalMinutes: Double?` and `private var wasEnabled = false`. If `enabled && (!wasEnabled || scheduledIntervalMinutes != settings.breakIntervalMinutes)`, clear `nextFire` so the next `evaluate` starts a full interval. Then set `wasEnabled = enabled` and `scheduledIntervalMinutes = settings.breakIntervalMinutes`.

Timer: `Timer.publish(every: 1, on: .main, in: .common).autoconnect()` stored in a `Set<AnyCancellable>`, **only while enabled**. Invalidate / cancel when disabled.

Also subscribe to:

- `settings.$breakRemindersEnabled`
- `settings.$breakIntervalMinutes`
- `NSWorkspace.didWakeNotification`

Each subscription calls `evaluate()`.

`AppSession.init` after settings exist:

```swift
self.breakClock = BreakReminderClock(settings: settings, alerts: .shared)
```

Expose `let breakClock: BreakReminderClock` on `AppSession`.

Do **not** put a 1 Hz `@Published` on `AirPostureSettings`. Only the clock ticks.

- [ ] **Step 1: Implement the clock file and wire it on `AppSession`.** There is no isolated XCTest for the timer; the core `isDue` / `nextFireDate` tests already lock the math. Keep `evaluate` small enough to match the bullets above line-for-line.

- [ ] **Step 2: `swift build` the app target** (or `./build.sh debug`) and fix compile errors. Do not open the app yet if UI is still missing — Task 5 adds the label.

If `BreakKind` / `BreakBanner` need `#if SWIFT_PACKAGE import AirPostureCore` in the clock file, add the same import pattern used by `AirPostureSettings.swift`.

- [ ] **Step 3: Do not commit**

---

### Task 5: Menu-bar countdown, popover HUD, options, README, Xcode

**Files:**
- Modify: `Sources/AirPostureMac/AirPostureMacApp.swift`
- Modify: `Sources/AirPostureMac/MenuBarIcon.swift`
- Modify: `Sources/AirPostureMac/MenuBarView.swift`
- Modify: `AirPostureMac.xcodeproj/project.pbxproj`
- Modify: `README.md`

**Menu-bar extra label (required):**

Replace the current `MenuBarIcon(...)` label with a small view that still draws the existing icon and, **only when `breakClock.isEnabled`**, shows `breakClock.statusItemText` to the right in a monospaced-digit caption. Use a 4 pt gap. Do not replace the posture symbol.

```swift
struct MenuBarStatusLabel: View {
    @ObservedObject var tracker: PostureTrackingManager
    @ObservedObject var settings: AirPostureSettings
    @ObservedObject var breakClock: BreakReminderClock

    var body: some View {
        HStack(spacing: 4) {
            MenuBarIcon(tracker: tracker, settings: settings, breakClock: breakClock)
            if breakClock.isEnabled {
                Text(breakClock.statusItemText)
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
```

When the feature is off, the extra is icon-only — same width as today.

**VoiceOver:** extend `MenuBarIcon`’s label. Add an optional `BreakReminderClock` (or pass `isEnabled` + remaining string). If enabled, append `", break in \(accessibilityRemaining)"` to every existing phrase. Example: `AirPosture, upright, break in 24 minutes`.

**Popover HUD row:** in `MenuBarView.content`, **between `header` and `PostureGaugeView`**, show this only when `breakClock.isEnabled`:

```swift
HStack(spacing: 8) {
    Image(systemName: breakSymbol)
    Text(breakClock.popoverText)
        .font(.body.monospacedDigit())
    Text("to break")
        .foregroundStyle(.secondary)
    Spacer()
    Text(settings.breakKind.title)
        .foregroundStyle(.secondary)
}
.accessibilityElement(children: .combine)
.accessibilityLabel("Break reminder, \(breakClock.accessibilityRemaining) remaining, \(settings.breakKind.title)")
```

Symbols: walk `figure.walk`, water `drop`, eyes `eye`, mix `clock`.

**Options:** add a new `settingsGroup("Breaks", systemImage: "cup.and.saucer")` **above** the existing Reminders group (slouch visuals stay under Reminders). Contents:

1. `settingsToggle("Break reminders", isOn: $settings.breakRemindersEnabled, help: "Repeating banner and sound to stand up, drink water, or rest your eyes. Off by default.")`
2. Interval slider: title `Interval`, `valueText` `"\(Int(settings.breakIntervalMinutes))m"`, range `5...120`, step `5`, help `How long between break reminders.`
3. `labeledPicker("Break type", selection: $settings.breakKind)` with `ForEach(BreakKind.allCases)`.

Disable interval + kind when the toggle is off (same `.disabled` / opacity pattern as turn-away angle).

Inject `breakClock` with `.environmentObject(session.breakClock)` next to the other environment objects.

**Xcode `project.pbxproj`:** add these IDs (they are unused):

```
A20000000000000000000030 /* BreakReminder.swift */ path = ../AirPostureCore/BreakReminder.swift
A20000000000000000000031 /* BreakReminderClock.swift */ path = BreakReminderClock.swift
A10000000000000000000030 /* BreakReminder.swift in Sources */
A10000000000000000000031 /* BreakReminderClock.swift in Sources */
```

Add the file refs to the `AirPostureMac` group and both names to `PBXSourcesBuildPhase`. Match the `BustAnimation.swift` / `WarningIntensity.swift` core-file style.

**README.md:**

In **Using the console**, after the Options bullet, add a bullet:

- **Breaks** — off by default. When enabled, a countdown appears in the menu bar and at the top of the popover. At zero, AirPosture plays the selected sound and a Walk, Water, or Eyes banner (Mix rotates those three). Snooze and Focus silence that tap; the next interval starts immediately with no backlog. Breaks never draw the slouch overlay and do not change weekly stats.

In the **Customization** table, add:

| Break reminders | Off | Repeating interval 5–120 minutes (default 45). Walk / Water / Eyes / Mix. |

- [ ] **Step 1: Wire the label, HUD row, options, environment objects, pbxproj, README.**
- [ ] **Step 2: Build**

```bash
./build.sh debug
```

Expected: `AirPosture.app` builds and signs. If Xcode is unavailable, SwiftPM bundle success is enough; still edit `pbxproj` so the Xcode path compiles later.

- [ ] **Step 3: Do not commit**

---

### Task 6: Verification

- [ ] **Step 1: Focused core**

```bash
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/airposture-make/clang-module-cache" \
  swift run --disable-sandbox \
  --cache-path "${TMPDIR:-/tmp}/airposture-make/cache" \
  --config-path "${TMPDIR:-/tmp}/airposture-make/config" \
  --security-path "${TMPDIR:-/tmp}/airposture-make/security" \
  AirPostureFeatureCheck breaks
```

Expected: `AirPosture feature checks passed: breaks`

- [ ] **Step 2: Full automated suite**

```bash
make test
```

Expected: feature / mapping / bust checks pass, then native settings + sound + store checks pass.

- [ ] **Step 3: App compile**

```bash
./build.sh debug
```

- [ ] **Step 4: Human QA checklist (report as pending if you cannot click the live extra)**

1. Fresh launch: menu bar is icon-only. No break banner.
2. Options → Breaks → enable, interval 5 minutes, type Water. Menu bar shows `5m` (then ticks). Popover row shows `5:00` counting down and `Water`.
3. Disable: countdown disappears from extra and popover.
4. Re-enable and switch interval 5 → 15: countdown jumps back to a full 15 minutes.
5. While enabled, snooze 15 minutes and let a due instant occur (temporarily use a debug 5s interval **only if you add a temporary override; otherwise wait or call `evaluate` from a DEBUG hook — do not ship a debug interval**). Preferred: in DEBUG, you may temporarily construct the clock with `now` advancing in a fixture; do not leave a hidden launch flag. If you cannot fire live, say so.
6. Confirm a Water banner uses title/body above and notification id is not visible to the user as slouch copy.
7. Confirm Glow / slouch overlay does **not** appear for a break fire.
8. Confirm week stats do not gain an episode from a break fire.
9. Mix: three successive eligible fires are Walk, then Water, then Eyes.
10. Focus on + authorized: due instant plays nothing and posts nothing; countdown restarts.

Do not claim 5–10 from unit tests alone.

---

## Out of scope

- Kitchen-timer / one-shot mode
- Wall-clock times of day
- Pause tracking during a break
- Coolio-guided reset
- Overlay / dim for breaks
- Persisting leftover countdown across launch
- Backlog of missed breaks
- New sound pack
- Login item
- Changing slouch Focus policy
