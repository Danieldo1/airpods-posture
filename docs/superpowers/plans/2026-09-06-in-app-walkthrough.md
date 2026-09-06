# In-App Walkthrough Implementation Plan

> **For Codex / agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work and review uncommitted diffs. Do **not** commit, branch, or start a long-lived process unless the operator explicitly asks.

**Goal:** First-open the menu-bar popover on a 6-step How AirPosture works walkthrough, and let people replay it from the footer, without changing scoring, overlays, or analytics.

**Architecture:** Put step order, exact copy, next/back, and existing-user migration rules in `AirPostureCore.Walkthrough`. Persist only `hasCompletedWalkthrough` on `AirPostureSettings`. Present `WalkthroughView` in place of the popover scroll body (header and footer stay). Existing users who already have a Desk or Sofa baseline skip the first-run card.

**Tech Stack:** Swift 5.9 / macOS 14+, SwiftUI `MenuBarExtra` `.window`, UserDefaults, existing executable-check harness (no XCTest).

## Codex operator prompt

Paste this as the Codex task. This plan file is the source of truth.

```xml
<task>
Implement docs/superpowers/plans/2026-09-06-in-app-walkthrough.md in /Users/Daniel_1/Desktop/mac-posture.
Add a 6-step first-open walkthrough inside the existing menu-bar popover, plus a footer How it works replay.
Follow the plan task-by-task. Do not invent a different architecture.
</task>

<completeness_contract>
Finish every task: core model + feature checks, settings persistence and migrate, tracker hasAnyCalibration, WalkthroughView in MenuBarView, footer replay, pbxproj, UI fixture stay-on-console, verification.
Do not stop after the core types. The walkthrough must replace the popover scroll body on first open for a user with no saved Neutral.
</completeness_contract>

<default_follow_through_policy>
Keep going. Prefer the plan’s types, names, copy, and file paths over improvisation.
Only stop if a required production API is missing and cannot be inferred from the plan or existing MenuBarView / settings code.
</default_follow_through_policy>

<verification_loop>
After implementation, run the exact commands in the plan’s verification section.
Do not claim the first-open popover behavior from a compile alone. Report which checks passed and which native QA still needs a human.
</verification_loop>

<action_safety>
No commits, no branches, no force-git, no package-manager upgrades.
Do not change slouch ellipse math, grace, overlay rendering, Coolio / SceneKit, weekly analytics, or break-reminder timing.
Do not rewrite README.md. That is a separate plan: docs/superpowers/plans/2026-09-06-nontechnical-readme.md.
Do not add a new Window / Settings scene, Dock icon, or auto-open of the MenuBarExtra.
Do not revert unrelated uncommitted files.
</action_safety>
```

## Locked product decisions

These are already decided. Do not reopen them.

| Decision | Value |
|---|---|
| Surface | Same 360-pt menu-bar popover. Replace **scroll body only**. Header (title, Desk/Sofa, connection badge) and footer stay |
| Trigger | First time the popover appears while `hasCompletedWalkthrough` is false |
| Auto-open popover | **No**. The user still clicks the menu-bar icon |
| Pages | 6, in this order: Welcome → Headphones → Motion → Neutral → Reminders → Ready |
| Skip | On pages 1–5. Marks completed and shows the normal console |
| Done | Last page only. Same as Skip: marks completed and shows the console |
| Back | Hidden on page 1 |
| Replay | Footer button **How it works** starts at Welcome again. Does not clear `hasCompletedWalkthrough` |
| Existing users | If the completion key has **never been written** and Desk **or** Sofa already has a stored baseline, mark completed and do **not** show the card |
| Calibrate during tour | Show the real Set Neutral Posture control on the Neutral page. Calibrating does **not** auto-advance |
| Live status | Headphones page shows `tracker.connectionStatus.title`. Motion page shows the existing permission sentence when `authorizationDenied` |
| New windows | None |
| README.md | Out of scope |

### Page copy (exact)

Use these strings verbatim. Do not mention IMU, pitch, ellipse, Core Motion, or APIs.

| Step | Title | Body | Primary | Extra UI |
|---|---|---|---|---|
| `welcome` | Welcome to AirPosture | AirPosture lives in the menu bar. It uses the motion sensors in compatible AirPods to notice when your head stays tilted or leaned, then nudges you to sit up. Nothing is sent off this Mac. | Next | — |
| `headphones` | Connect your AirPods | Put on AirPods Pro, AirPods Max, AirPods 3 or 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 cannot do this. The badge in the header turns Connected when they are ready. | Next | Live status line: `Headphones` + `tracker.connectionStatus.title` |
| `motion` | Allow Motion & Fitness | macOS will ask for Motion & Fitness so AirPosture can read those sensors. If you already tapped Don’t Allow, open System Settings → Privacy & Security → Motion & Fitness and turn AirPosture on. | Next | If `authorizationDenied`, also show: `Motion access is off. Enable it in System Settings → Privacy & Security → Motion & Fitness.` |
| `calibrate` | Set your Neutral Posture | Sit the way you want to hold yourself. Then press Set Neutral Posture. Desk and Sofa remember different sitting positions — switch the preset and set Neutral again when you change how you sit. | Next | Same Set Neutral Posture button behavior as the console (disabled when `!tracker.canCalibrate`, ⌘K, “Neutral Posture Saved” after calibrate) |
| `nudges` | How reminders work | A faint Glow can appear as you start to slouch. If you stay past your Neutral for a few seconds, AirPosture plays a sound and can show a Sit up straight! banner. Press Esc during a warning to snooze 15 minutes. The Glow never blocks clicks. | Next | — |
| `ready` | You’re set | Leave tracking on and wear your AirPods. Open Options anytime to change sensitivity, sounds, or optional break reminders. Replay these steps from How it works at the bottom of this window. | Done | — |

### Navigation chrome (exact)

- Progress label: `1 of 6` … `6 of 6` (1-based). VoiceOver: `Step 1 of 6`.
- Skip label: `Skip` (pages 1–5 only).
- Back label: `Back`.
- Container VoiceOver label: `How AirPosture works`.

### Completion key (exact)

- UserDefaults key: `hasCompletedWalkthrough`
- **Do not** `register` this key. `register` would make `object(forKey:)` non-nil and hide first-run vs existing-user.
- Missing key + no calibration → first-run walkthrough.
- Missing key + any stored baseline → migrate to `true`.
- Key already present (true or false) → leave it. Skip/Done write `true`.

---

## Global Constraints

- Work on the current checkout. Do not create a branch, commit, or start a long-lived process.
- Preserve unrelated uncommitted files.
- macOS 14+ (`Package.swift` platforms). No new dependencies.
- Installed Command Line Tools have no XCTest. Use `expectEqual` / `expectValue` / `expectTrue` helpers and `exit(1)`.
- Native compile uses a temp module cache. Prefer `make test`. Fallback: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`.
- `AirPostureFeatureCheck` can import `AirPostureCore` only. Settings tests stay in `Tests/run-native-checks.sh`.
- `AirPostureSettings` is compiled into native checks **without** the AirPostureCore module unless those Swift files are listed. If settings calls `Walkthrough.shouldMigrateAsCompleted`, `Tests/run-native-checks.sh` must also compile `Sources/AirPostureCore/Walkthrough.swift` in `SETTINGS_SOURCES`.
- Xcode target lists files explicitly in `AirPostureMac.xcodeproj/project.pbxproj`. New Swift files need unused `A1…` build-file IDs and `A2…` file-ref IDs.
- Walkthrough body width must stay 360 pt. Do not introduce horizontal scrolling.

---

## File structure

- Create: `Sources/AirPostureCore/Walkthrough.swift` — steps, copy, next/back, migrate/auto-present rules.
- Create: `Tests/AirPostureFeatureCheck/WalkthroughChecks.swift` — core assertions.
- Create: `Sources/AirPostureMac/WalkthroughView.swift` — popover page UI.
- Modify: `Tests/AirPostureFeatureCheck/main.swift` — register group `walkthrough`.
- Modify: `Sources/AirPostureMac/AirPostureSettings.swift` — `hasCompletedWalkthrough`, `isWalkthroughPresented`, `completeWalkthrough()`, `migrateWalkthroughIfNeeded(hasAnyCalibration:)`.
- Modify: `Tests/AirPostureSettingsCheck/main.swift` — default, persist, migrate cases.
- Modify: `Sources/AirPostureMac/PostureTrackingManager.swift` — public `hasAnyCalibration`.
- Modify: `Sources/AirPostureMac/AirPostureMacApp.swift` — migrate + set initial presentation in `AppSession`.
- Modify: `Sources/AirPostureMac/MenuBarView.swift` — swap scroll body; footer **How it works**.
- Modify: `Tests/AirPostureUIFixture/main.swift` — mark walkthrough completed so Console stays the console; add a Walkthrough preview page.
- Modify: `Tests/run-native-checks.sh` — compile `Walkthrough.swift` with settings sources.
- Modify: `AirPostureMac.xcodeproj/project.pbxproj` — add both new Swift files.
- Do **not** modify `README.md`, overlay, tracker scoring, bust, analytics, or break-reminder files except unused-import compile fixes (there should be none).

---

### Task 1: Core walkthrough model

**Files:**
- Create: `Sources/AirPostureCore/Walkthrough.swift`
- Create: `Tests/AirPostureFeatureCheck/WalkthroughChecks.swift`
- Modify: `Tests/AirPostureFeatureCheck/main.swift`

**Interfaces:**

```swift
public enum WalkthroughStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case headphones
    case motion
    case calibrate
    case nudges
    case ready
}

public struct WalkthroughPage: Equatable, Sendable {
    public let step: WalkthroughStep
    public let title: String
    public let body: String
    public let primaryTitle: String
    public let showsBack: Bool
    public let showsSkip: Bool
    public let showsConnectionStatus: Bool
    public let showsCalibrateControl: Bool
    public let showsMotionDeniedHint: Bool
}

public enum Walkthrough {
    public static let stepCount = 6

    public static func page(for step: WalkthroughStep) -> WalkthroughPage
    public static func advance(_ step: WalkthroughStep) -> WalkthroughStep?
    public static func back(_ step: WalkthroughStep) -> WalkthroughStep?
    public static func clamp(_ raw: Int) -> WalkthroughStep
    public static func displayIndex(_ step: WalkthroughStep) -> Int
    public static func progressText(_ step: WalkthroughStep) -> String
    public static func accessibilityProgress(_ step: WalkthroughStep) -> String
    public static func shouldAutoPresent(hasCompleted: Bool) -> Bool
    public static func shouldMigrateAsCompleted(hasCompletionKey: Bool, hasAnyCalibration: Bool) -> Bool
}
```

`advance`: `WalkthroughStep(rawValue: step.rawValue + 1)` — `nil` on `ready`.

`back`: `WalkthroughStep(rawValue: step.rawValue - 1)` — `nil` on `welcome`.

`clamp`: if `raw` is outside `0...5`, return `.welcome` for values `< 0` and `.ready` for values `> 5`.

`displayIndex`: `step.rawValue + 1`.

`progressText`: `"\(displayIndex(step)) of \(stepCount)"`.

`accessibilityProgress`: `"Step \(displayIndex(step)) of \(stepCount)"`.

`shouldAutoPresent`: `!hasCompleted`.

`shouldMigrateAsCompleted`: `!hasCompletionKey && hasAnyCalibration`.

`page(for:)` fills the table above. Flags:

| Step | showsBack | showsSkip | showsConnectionStatus | showsCalibrateControl | showsMotionDeniedHint |
|---|---|---|---|---|---|
| welcome | false | true | false | false | false |
| headphones | true | true | true | false | false |
| motion | true | true | false | false | true |
| calibrate | true | true | false | true | false |
| nudges | true | true | false | false | false |
| ready | true | false | false | false | false |

`primaryTitle` is `Next` on every step except `ready`, which is `Done`.

- [ ] **Step 1: Write the failing feature checks**

Create `Tests/AirPostureFeatureCheck/WalkthroughChecks.swift`. Reuse `expectTrue` / `expectValue` from `BreakReminderChecks.swift` if they are file-level in that module (they are). Do not duplicate those helpers.

```swift
import AirPostureCore
import Foundation

func runWalkthroughChecks() {
    expectValue(Walkthrough.stepCount, 6, "six steps")
    expectValue(WalkthroughStep.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5], "raw values are contiguous")

    expectValue(Walkthrough.advance(.welcome), .headphones, "advance welcome")
    expectValue(Walkthrough.advance(.nudges), .ready, "advance nudges")
    expectTrue(Walkthrough.advance(.ready) == nil, "advance past last is nil")
    expectTrue(Walkthrough.back(.welcome) == nil, "back from first is nil")
    expectValue(Walkthrough.back(.headphones), .welcome, "back headphones")
    expectValue(Walkthrough.back(.ready), .nudges, "back ready")

    expectValue(Walkthrough.clamp(-3), .welcome, "clamp low")
    expectValue(Walkthrough.clamp(0), .welcome, "clamp welcome")
    expectValue(Walkthrough.clamp(5), .ready, "clamp ready")
    expectValue(Walkthrough.clamp(99), .ready, "clamp high")

    expectValue(Walkthrough.displayIndex(.welcome), 1, "first page is 1")
    expectValue(Walkthrough.displayIndex(.ready), 6, "last page is 6")
    expectValue(Walkthrough.progressText(.motion), "3 of 6", "progress text")
    expectValue(Walkthrough.accessibilityProgress(.motion), "Step 3 of 6", "progress a11y")

    expectTrue(Walkthrough.shouldAutoPresent(hasCompleted: false), "incomplete auto-presents")
    expectTrue(!Walkthrough.shouldAutoPresent(hasCompleted: true), "completed does not auto-present")

    expectTrue(
        Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: false, hasAnyCalibration: true),
        "existing calibrated user migrates"
    )
    expectTrue(
        !Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: false, hasAnyCalibration: false),
        "brand-new user does not migrate"
    )
    expectTrue(
        !Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: true, hasAnyCalibration: true),
        "written key is left alone"
    )
    expectTrue(
        !Walkthrough.shouldMigrateAsCompleted(hasCompletionKey: true, hasAnyCalibration: false),
        "written key without calibration is left alone"
    )

    let welcome = Walkthrough.page(for: .welcome)
    expectValue(welcome.title, "Welcome to AirPosture", "welcome title")
    expectValue(
        welcome.body,
        "AirPosture lives in the menu bar. It uses the motion sensors in compatible AirPods to notice when your head stays tilted or leaned, then nudges you to sit up. Nothing is sent off this Mac.",
        "welcome body"
    )
    expectValue(welcome.primaryTitle, "Next", "welcome primary")
    expectTrue(!welcome.showsBack && welcome.showsSkip, "welcome chrome")
    expectTrue(!welcome.showsConnectionStatus && !welcome.showsCalibrateControl && !welcome.showsMotionDeniedHint, "welcome extras off")

    let headphones = Walkthrough.page(for: .headphones)
    expectValue(headphones.title, "Connect your AirPods", "headphones title")
    expectValue(
        headphones.body,
        "Put on AirPods Pro, AirPods Max, AirPods 3 or 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 cannot do this. The badge in the header turns Connected when they are ready.",
        "headphones body"
    )
    expectTrue(headphones.showsConnectionStatus, "headphones shows status")

    let motion = Walkthrough.page(for: .motion)
    expectValue(motion.title, "Allow Motion & Fitness", "motion title")
    expectValue(
        motion.body,
        "macOS will ask for Motion & Fitness so AirPosture can read those sensors. If you already tapped Don’t Allow, open System Settings → Privacy & Security → Motion & Fitness and turn AirPosture on.",
        "motion body"
    )
    expectTrue(motion.showsMotionDeniedHint, "motion may show denied hint")

    let calibrate = Walkthrough.page(for: .calibrate)
    expectValue(calibrate.title, "Set your Neutral Posture", "calibrate title")
    expectValue(
        calibrate.body,
        "Sit the way you want to hold yourself. Then press Set Neutral Posture. Desk and Sofa remember different sitting positions — switch the preset and set Neutral again when you change how you sit.",
        "calibrate body"
    )
    expectTrue(calibrate.showsCalibrateControl, "calibrate shows button")

    let nudges = Walkthrough.page(for: .nudges)
    expectValue(nudges.title, "How reminders work", "nudges title")
    expectValue(
        nudges.body,
        "A faint Glow can appear as you start to slouch. If you stay past your Neutral for a few seconds, AirPosture plays a sound and can show a Sit up straight! banner. Press Esc during a warning to snooze 15 minutes. The Glow never blocks clicks.",
        "nudges body"
    )
    expectValue(nudges.primaryTitle, "Next", "nudges primary")

    let ready = Walkthrough.page(for: .ready)
    expectValue(ready.title, "You’re set", "ready title")
    expectValue(
        ready.body,
        "Leave tracking on and wear your AirPods. Open Options anytime to change sensitivity, sounds, or optional break reminders. Replay these steps from How it works at the bottom of this window.",
        "ready body"
    )
    expectValue(ready.primaryTitle, "Done", "ready primary")
    expectTrue(ready.showsBack && !ready.showsSkip, "ready chrome")
}
```

In `Tests/AirPostureFeatureCheck/main.swift`, add `"walkthrough"` to the default groups and the switch:

```swift
    case "walkthrough":
        runWalkthroughChecks()
```

Default groups become `["warnings", "analytics", "breaks", "walkthrough"]`.

- [ ] **Step 2: Run the walkthrough group and confirm it fails**

```bash
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/airposture-make/clang-module-cache" \
  swift run --disable-sandbox \
  --cache-path "${TMPDIR:-/tmp}/airposture-make/cache" \
  --config-path "${TMPDIR:-/tmp}/airposture-make/config" \
  --security-path "${TMPDIR:-/tmp}/airposture-make/security" \
  AirPostureFeatureCheck walkthrough
```

Expected: compile error (`Walkthrough` not found) or FAIL assertions.

- [ ] **Step 3: Implement `Sources/AirPostureCore/Walkthrough.swift`**

```swift
public enum WalkthroughStep: Int, CaseIterable, Sendable {
    case welcome = 0
    case headphones
    case motion
    case calibrate
    case nudges
    case ready
}

public struct WalkthroughPage: Equatable, Sendable {
    public let step: WalkthroughStep
    public let title: String
    public let body: String
    public let primaryTitle: String
    public let showsBack: Bool
    public let showsSkip: Bool
    public let showsConnectionStatus: Bool
    public let showsCalibrateControl: Bool
    public let showsMotionDeniedHint: Bool
}

public enum Walkthrough {
    public static let stepCount = 6

    public static func page(for step: WalkthroughStep) -> WalkthroughPage {
        switch step {
        case .welcome:
            return WalkthroughPage(
                step: step,
                title: "Welcome to AirPosture",
                body: "AirPosture lives in the menu bar. It uses the motion sensors in compatible AirPods to notice when your head stays tilted or leaned, then nudges you to sit up. Nothing is sent off this Mac.",
                primaryTitle: "Next",
                showsBack: false,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .headphones:
            return WalkthroughPage(
                step: step,
                title: "Connect your AirPods",
                body: "Put on AirPods Pro, AirPods Max, AirPods 3 or 4, or other Apple headphones with spatial audio head tracking. Original AirPods and AirPods 2 cannot do this. The badge in the header turns Connected when they are ready.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: true,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .motion:
            return WalkthroughPage(
                step: step,
                title: "Allow Motion & Fitness",
                body: "macOS will ask for Motion & Fitness so AirPosture can read those sensors. If you already tapped Don’t Allow, open System Settings → Privacy & Security → Motion & Fitness and turn AirPosture on.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: true
            )
        case .calibrate:
            return WalkthroughPage(
                step: step,
                title: "Set your Neutral Posture",
                body: "Sit the way you want to hold yourself. Then press Set Neutral Posture. Desk and Sofa remember different sitting positions — switch the preset and set Neutral again when you change how you sit.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: true,
                showsMotionDeniedHint: false
            )
        case .nudges:
            return WalkthroughPage(
                step: step,
                title: "How reminders work",
                body: "A faint Glow can appear as you start to slouch. If you stay past your Neutral for a few seconds, AirPosture plays a sound and can show a Sit up straight! banner. Press Esc during a warning to snooze 15 minutes. The Glow never blocks clicks.",
                primaryTitle: "Next",
                showsBack: true,
                showsSkip: true,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        case .ready:
            return WalkthroughPage(
                step: step,
                title: "You’re set",
                body: "Leave tracking on and wear your AirPods. Open Options anytime to change sensitivity, sounds, or optional break reminders. Replay these steps from How it works at the bottom of this window.",
                primaryTitle: "Done",
                showsBack: true,
                showsSkip: false,
                showsConnectionStatus: false,
                showsCalibrateControl: false,
                showsMotionDeniedHint: false
            )
        }
    }

    public static func advance(_ step: WalkthroughStep) -> WalkthroughStep? {
        WalkthroughStep(rawValue: step.rawValue + 1)
    }

    public static func back(_ step: WalkthroughStep) -> WalkthroughStep? {
        WalkthroughStep(rawValue: step.rawValue - 1)
    }

    public static func clamp(_ raw: Int) -> WalkthroughStep {
        if raw < 0 { return .welcome }
        if raw > stepCount - 1 { return .ready }
        return WalkthroughStep(rawValue: raw) ?? .welcome
    }

    public static func displayIndex(_ step: WalkthroughStep) -> Int {
        step.rawValue + 1
    }

    public static func progressText(_ step: WalkthroughStep) -> String {
        "\(displayIndex(step)) of \(stepCount)"
    }

    public static func accessibilityProgress(_ step: WalkthroughStep) -> String {
        "Step \(displayIndex(step)) of \(stepCount)"
    }

    public static func shouldAutoPresent(hasCompleted: Bool) -> Bool {
        !hasCompleted
    }

    public static func shouldMigrateAsCompleted(hasCompletionKey: Bool, hasAnyCalibration: Bool) -> Bool {
        !hasCompletionKey && hasAnyCalibration
    }
}
```

`Package.swift` already includes every file under `Sources/AirPostureCore`. Do not edit it.

- [ ] **Step 4: Re-run the walkthrough group**

Same command as Step 2.

Expected: `AirPosture feature checks passed: walkthrough`

- [ ] **Step 5: Do not commit**

---

### Task 2: Persistence, migrate, and launch presentation

**Files:**
- Modify: `Sources/AirPostureMac/AirPostureSettings.swift`
- Modify: `Tests/AirPostureSettingsCheck/main.swift`
- Modify: `Sources/AirPostureMac/PostureTrackingManager.swift`
- Modify: `Sources/AirPostureMac/AirPostureMacApp.swift`
- Modify: `Tests/run-native-checks.sh`

**Interfaces:**

```swift
// AirPostureSettings
@Published var hasCompletedWalkthrough: Bool  // persisted
@Published var isWalkthroughPresented: Bool   // memory only, default false

func completeWalkthrough()
func startWalkthrough()
func migrateWalkthroughIfNeeded(hasAnyCalibration: Bool)

// PostureTrackingManager
var hasAnyCalibration: Bool { get }  // deskPitchDegrees != nil || sofaPitchDegrees != nil
```

`completeWalkthrough()` sets `hasCompletedWalkthrough = true` and `isWalkthroughPresented = false`.

`startWalkthrough()` sets `isWalkthroughPresented = true` only. It does **not** clear `hasCompletedWalkthrough`.

`migrateWalkthroughIfNeeded`:

```swift
func migrateWalkthroughIfNeeded(hasAnyCalibration: Bool) {
    let hasKey = defaults.object(forKey: Key.hasCompletedWalkthrough) != nil
    guard Walkthrough.shouldMigrateAsCompleted(
        hasCompletionKey: hasKey,
        hasAnyCalibration: hasAnyCalibration
    ) else { return }
    hasCompletedWalkthrough = true
}
```

Init read:

```swift
hasCompletedWalkthrough = defaults.object(forKey: Key.hasCompletedWalkthrough) as? Bool ?? false
isWalkthroughPresented = false
```

Do **not** add `hasCompletedWalkthrough` to `defaults.register(defaults:)`.

`AppSession.init` after `tracker.configure` and creating settings:

```swift
settings.migrateWalkthroughIfNeeded(hasAnyCalibration: tracker.hasAnyCalibration)
settings.isWalkthroughPresented = Walkthrough.shouldAutoPresent(
    hasCompleted: settings.hasCompletedWalkthrough
)
```

`SETTINGS_SOURCES` in `Tests/run-native-checks.sh` becomes:

```bash
SETTINGS_SOURCES=(
  Sources/AirPostureCore/WarningIntensity.swift
  Sources/AirPostureCore/BreakReminder.swift
  Sources/AirPostureCore/Walkthrough.swift
  Sources/AirPostureMac/AirPostureSettings.swift
)
```

- [ ] **Step 1: Write the failing settings checks**

Add `checkWalkthroughPersistenceAndMigrate()` and call it from `main()`:

```swift
@MainActor
private func checkWalkthroughPersistenceAndMigrate() {
    withDefaults { defaults in
        let settings = AirPostureSettings(defaults: defaults)
        expectEqual(settings.hasCompletedWalkthrough, false, "walkthrough defaults incomplete")
        expectEqual(settings.isWalkthroughPresented, false, "presentation is memory-only default")
        expectEqual(defaults.object(forKey: "hasCompletedWalkthrough") == nil, true, "completion key is not registered")

        settings.migrateWalkthroughIfNeeded(hasAnyCalibration: false)
        expectEqual(settings.hasCompletedWalkthrough, false, "new user is not migrated")

        settings.migrateWalkthroughIfNeeded(hasAnyCalibration: true)
        expectEqual(settings.hasCompletedWalkthrough, true, "calibrated user migrates")
        expectEqual(defaults.bool(forKey: "hasCompletedWalkthrough"), true, "migrate writes the key")
    }

    withDefaults { defaults in
        defaults.set(false, forKey: "hasCompletedWalkthrough")
        let settings = AirPostureSettings(defaults: defaults)
        settings.migrateWalkthroughIfNeeded(hasAnyCalibration: true)
        expectEqual(settings.hasCompletedWalkthrough, false, "explicit false is not overwritten")
    }

    withDefaults { defaults in
        let settings = AirPostureSettings(defaults: defaults)
        settings.startWalkthrough()
        expectEqual(settings.isWalkthroughPresented, true, "start presents")
        expectEqual(settings.hasCompletedWalkthrough, false, "start does not complete")
        expectEqual(defaults.object(forKey: "hasCompletedWalkthrough") == nil, true, "start does not write the key")

        settings.completeWalkthrough()
        expectEqual(settings.hasCompletedWalkthrough, true, "complete marks done")
        expectEqual(settings.isWalkthroughPresented, false, "complete dismisses")

        let reloaded = AirPostureSettings(defaults: defaults)
        expectEqual(reloaded.hasCompletedWalkthrough, true, "completion persists")
        expectEqual(reloaded.isWalkthroughPresented, false, "presentation does not persist")
    }
}
```

- [ ] **Step 2: Run settings checks and confirm new asserts fail**

```bash
Tests/run-native-checks.sh
```

You may run only the settings compile by invoking the script as `checks` (default). Expected: FAIL on the new names until settings exists.

- [ ] **Step 3: Implement settings + tracker + AppSession**

Add to `AirPostureSettings.Key`:

```swift
static let hasCompletedWalkthrough = "hasCompletedWalkthrough"
```

Add the two published properties, `didSet` persist **only** `hasCompletedWalkthrough`, and the three methods.

On `PostureTrackingManager`, next to `isCalibrated`:

```swift
var hasAnyCalibration: Bool {
    deskPitchDegrees != nil || sofaPitchDegrees != nil
}
```

Wire `AppSession.init` as specified. Do not request notifications differently. Do not change `AppDelegate`.

- [ ] **Step 4: Re-run native checks**

```bash
Tests/run-native-checks.sh
```

Expected: `AirPosture settings checks passed` and the other native checks still pass.

- [ ] **Step 5: Do not commit**

---

### Task 3: Popover UI

**Files:**
- Create: `Sources/AirPostureMac/WalkthroughView.swift`
- Modify: `Sources/AirPostureMac/MenuBarView.swift`

**Interfaces:**

```swift
struct WalkthroughView: View {
    @Binding var step: WalkthroughStep
    let connectionTitle: String
    let authorizationDenied: Bool
    let canCalibrate: Bool
    let didJustCalibrate: Bool
    let onCalibrate: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void
}
```

`WalkthroughView` owns Next/Back only. Next on `ready` calls `onFinish`. Skip calls `onSkip`. Both closures in `MenuBarView` call `settings.completeWalkthrough()` (which also clears `isWalkthroughPresented`).

- [ ] **Step 1: Add `WalkthroughView.swift`**

Layout (all inside width 360, leading-aligned, wrapping text):

```swift
var body: some View {
    let page = Walkthrough.page(for: step)
    VStack(alignment: .leading, spacing: 16) {
        Text(Walkthrough.progressText(step))
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Walkthrough.accessibilityProgress(step))

        Text(page.title)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)

        Text(page.body)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if page.showsConnectionStatus {
            HStack {
                Text("Headphones")
                Spacer()
                Text(connectionTitle)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Headphones, \(connectionTitle)")
        }

        if page.showsMotionDeniedHint, authorizationDenied {
            Text("Motion access is off. Enable it in System Settings → Privacy & Security → Motion & Fitness.")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if page.showsCalibrateControl {
            Button(action: onCalibrate) {
                Label(
                    didJustCalibrate ? "Neutral Posture Saved" : "Set Neutral Posture",
                    systemImage: didJustCalibrate ? "checkmark.circle.fill" : "scope"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCalibrate)
            .keyboardShortcut("k", modifiers: [.command])
        }

        Spacer(minLength: 12)

        HStack {
            if page.showsSkip {
                Button("Skip", action: onSkip)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if page.showsBack {
                Button("Back") {
                    if let previous = Walkthrough.back(step) {
                        step = previous
                    }
                }
            }
            Button(page.primaryTitle) {
                if let next = Walkthrough.advance(step) {
                    step = next
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .frame(width: 360)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("How AirPosture works")
}
```

Do not use `TabView` paging. Do not steal `Esc` (overlay snooze owns it). Honor Reduce Motion by skipping any page animation, or using `nil` animation when `accessibilityReduceMotion` is true.

- [ ] **Step 2: Swap the popover body and add the footer button**

In `MenuBarView`:

```swift
@State private var walkthroughStep = WalkthroughStep.welcome
```

Inside `ScrollView`, keep `.background(ConsoleScrollBehavior())` on whichever child is shown:

```swift
if settings.isWalkthroughPresented {
    WalkthroughView(
        step: $walkthroughStep,
        connectionTitle: tracker.connectionStatus.title,
        authorizationDenied: tracker.authorizationDenied,
        canCalibrate: tracker.canCalibrate,
        didJustCalibrate: tracker.didJustCalibrate,
        onCalibrate: handleCalibrate,
        onSkip: handleFinishWalkthrough,
        onFinish: handleFinishWalkthrough
    )
} else {
    content
}
```

Footer:

```swift
private var footer: some View {
    HStack {
        Text("v1.0.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        if !settings.isWalkthroughPresented {
            Button("How it works", action: handleStartWalkthrough)
                .font(.caption)
        }
        Spacer()
        Button("Quit AirPosture", action: handleQuit)
            .keyboardShortcut("q")
    }
}

private func handleStartWalkthrough() {
    walkthroughStep = .welcome
    settings.startWalkthrough()
}

private func handleFinishWalkthrough() {
    settings.completeWalkthrough()
}
```

`MenuBarView` already has `settings` as an `@EnvironmentObject`. Do not add a new scene.

- [ ] **Step 3: Build the app**

```bash
./build.sh debug
```

Expected: `AirPosture.app` builds and signs. If Xcode.app is missing, SwiftPM bundle success is enough; still edit `pbxproj` in Task 4.

- [ ] **Step 4: Do not commit**

---

### Task 4: Xcode project and UI fixture

**Files:**
- Modify: `AirPostureMac.xcodeproj/project.pbxproj`
- Modify: `Tests/AirPostureUIFixture/main.swift`

**Xcode IDs (unused today — use these exact values):**

```
A20000000000000000000033 /* Walkthrough.swift */ path = ../AirPostureCore/Walkthrough.swift
A20000000000000000000034 /* WalkthroughView.swift */ path = WalkthroughView.swift
A10000000000000000000033 /* Walkthrough.swift in Sources */
A10000000000000000000034 /* WalkthroughView.swift in Sources */
```

Add the file refs to the `AirPostureMac` group (next to `BreakReminder.swift` / `BreakReminderClock.swift`) and both names to `PBXSourcesBuildPhase`. Match the `BreakReminder.swift` core-file style (`path = ../AirPostureCore/Walkthrough.swift`).

**UI fixture:**

In `FixtureState.init`, after creating `settings`:

```swift
settings.hasCompletedWalkthrough = true
settings.isWalkthroughPresented = false
```

Add a fourth production-view page so humans can inspect the tour without wiping preferences:

```swift
Text("Walkthrough").tag("Walkthrough")
```

When `page == "Walkthrough"`:

```swift
WalkthroughView(
    step: $walkthroughStep,
    connectionTitle: state.tracker.connectionStatus.title,
    authorizationDenied: state.tracker.authorizationDenied,
    canCalibrate: state.tracker.canCalibrate,
    didJustCalibrate: state.tracker.didJustCalibrate,
    onCalibrate: { state.tracker.calibrate() },
    onSkip: { page = "Console" },
    onFinish: { page = "Console" }
)
```

Keep `@State private var walkthroughStep = WalkthroughStep.welcome` on `FixtureView`. Console smoke (`--smoke-console`) must still open `MenuBarView` with the walkthrough dismissed.

- [ ] **Step 1: Edit pbxproj and the fixture**
- [ ] **Step 2: Build**

```bash
./build.sh debug
```

- [ ] **Step 3: Do not commit**

---

### Task 5: Verification

- [ ] **Step 1: Focused core**

```bash
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/airposture-make/clang-module-cache" \
  swift run --disable-sandbox \
  --cache-path "${TMPDIR:-/tmp}/airposture-make/cache" \
  --config-path "${TMPDIR:-/tmp}/airposture-make/config" \
  --security-path "${TMPDIR:-/tmp}/airposture-make/security" \
  AirPostureFeatureCheck walkthrough
```

Expected: `AirPosture feature checks passed: walkthrough`

- [ ] **Step 2: Full automated suite**

```bash
make test
```

Expected: feature / mapping / bust checks pass, then native settings + sound + store + scroll checks pass.

- [ ] **Step 3: App compile**

```bash
./build.sh debug
```

- [ ] **Step 4: Human QA checklist (report as pending if you cannot click the live extra)**

1. **Brand-new preferences** (delete AirPosture keys or use a fresh user defaults suite / new macOS user): launch, click the menu-bar icon. Walkthrough page 1 shows **Welcome to AirPosture**. Bust, This week, and Options are hidden. Header still shows Desk/Sofa and the connection badge.
2. Next through all 6 pages. Copy matches the table. `1 of 6` … `6 of 6`. Back from page 2 returns to Welcome. Skip on page 1 jumps to the normal console and does not show the tour again after closing and reopening the popover.
3. Replay: footer **How it works** opens Welcome again. Done returns to the console. Quit and relaunch: tour stays dismissed.
4. Headphones page: disconnect AirPods → status text is not Connected. Connect → title becomes Connected (same word as the header badge).
5. Neutral page: Set Neutral Posture is disabled without connected headphones. With AirPods in, it saves and shows Neutral Posture Saved. The page does **not** auto-advance.
6. Existing-user migrate: on a defaults suite that already has `baselinePitchDegrees` (or sofa equivalent) and **no** `hasCompletedWalkthrough` key, launch opens the normal console, not the tour.
7. Two-finger scroll on a walkthrough page must not move horizontally.
8. Overlay, slouch sound, week stats, and break countdown still behave as before after Skip/Done.

Do not claim 1–8 from unit tests alone.

---

## Out of scope

- Rewriting `README.md` for non-technical readers (see `docs/superpowers/plans/2026-09-06-nontechnical-readme.md`)
- Coach-mark holes / spotlight around real controls
- Auto-opening the menu-bar popover
- A separate Help window or Settings scene
- Interactive Glow demo / forced slouch
- Changing ellipse math, grace, overlays, Coolio, analytics, or breaks
- Translating copy
- Login item / launch at login
