# Popover Scroll Isolation Implementation Plan

> **For Codex / agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work and review uncommitted diffs. Do **not** commit, branch, or start a long-lived process unless the operator explicitly asks.

**Goal:** Keep the menu-bar popover vertically scrollable and smooth while AirPods tracking is on, and stop two-finger horizontal scrolling.

**Architecture:** `ObservableObject` invalidates every view that holds the object when *any* `@Published` property is assigned. `MenuBarView` holds `PostureTrackingManager` as an `@EnvironmentObject`, so IMU samples currently rebuild the entire `ScrollView` (analytics, Options, ColorSelector) tens of times per second. Confirmed by the user: pausing Tracking makes scroll smooth. Move high-frequency pose onto a dedicated `LivePostureReadings` object that only `PostureGaugeView` observes. Keep `PostureTrackingManager` `@Published` writes to coarse chrome, and only assign them when the value actually changes. Restrict the console `ScrollView` to the vertical axis and clip overflow.

**Tech Stack:** Swift 5.9 / macOS 14+, SwiftUI `MenuBarExtra` `.window`, AppKit, Combine, existing executable-check harness (no XCTest).

**Diagnosis (do not relitigate):** Pausing Tracking removes `handleMotion` → `@Published` writes. That is the lag. Horizontal two-finger pan is the default SwiftUI `ScrollView` (both axes) plus any child wider than 360pt. Do **not** “fix” this by pausing SceneKit, lowering MSAA, throttling the whole tracker, or migrating to `@Observable`.

## Codex operator prompt

Paste this as the Codex task. The plan file is the source of truth.

```xml
<task>
Implement docs/superpowers/plans/2026-09-06-popover-scroll-isolation.md in /Users/Daniel_1/Desktop/mac-posture.
Fix two confirmed popover bugs: (1) vertical scroll hitch while Tracking is on, caused by IMU-rate ObservableObject invalidation of MenuBarView; (2) two-finger horizontal scrolling, caused by an unconstrained ScrollView plus overflow.
Follow the plan task-by-task. Do not invent a different architecture.
</task>

<completeness_contract>
Finish every task in the plan, including the failing-then-passing native check, SwiftUI wiring, vertical-only scroll, pbxproj/native-check script updates, and verification commands.
Do not stop after diagnosis. Do not leave the gauge reading live pose through MenuBarView.
</completeness_contract>

<default_follow_through_policy>
Keep going. Prefer the plan’s types, names, and file paths over improvisation.
Only stop if a required production API is missing and cannot be inferred from the plan or existing tracker code.
</default_follow_through_policy>

<verification_loop>
After implementation, run the exact commands in the plan’s verification section.
Do not claim the popover is smooth from a compile alone. Report which checks passed and which native QA still needs a human with AirPods.
</verification_loop>

<action_safety>
No commits, no branches, no force-git, no package-manager upgrades.
Do not edit InstrumentBustView, BustSceneRig, WeeklyAnalyticsStore sampling, WarningOverlayManager tick rate, Charts, or ColorSelector internals.
Do not migrate PostureTrackingManager to @Observable.
Do not revert unrelated uncommitted files (including .gitignore).
Keep public tracker getters used by overlay and Tests/AirPostureAnalyticsStoreCheck working.
</action_safety>
```

## Global Constraints

- Work on the current checkout. Do not create a branch, commit, or start a dev server.
- Preserve unrelated uncommitted files.
- macOS 14+ (`Package.swift` platforms). No new dependencies.
- Do not change scoring, analytics accumulation, overlay math, or bust rendering.
- `WarningOverlayManager` may keep reading `tracker` values on its 30 Hz timer. It must not require high-frequency `tracker.objectWillChange` to stay correct.
- Installed Command Line Tools have no XCTest. Use the existing executable-check pattern (`check` / `expectEqual`, `exit(1)` on failure).
- Native compile uses a temp module cache. Prefer `make test`. Fallback: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk`.
- SwiftPM executable `AirPostureFeatureCheck` cannot import `PostureTrackingManager` (that type lives in the app target). Tracker publication tests go in `Tests/AirPostureAnalyticsStoreCheck/main.swift`, which is concatenated with the tracker by `Tests/run-native-checks.sh`.

---

## File structure

- Create: `Sources/AirPostureMac/LivePostureReadings.swift` — high-frequency snapshot + `ObservableObject` used only by the hero gauge.
- Modify: `Sources/AirPostureMac/PostureTrackingManager.swift` — write live pose into `liveReadings`; stop `@Published`-assigning IMU fields; assign remaining published chrome only on change; keep existing getters for overlay/tests.
- Modify: `Sources/AirPostureMac/PostureGaugeView.swift` — observe `LivePostureReadings` instead of taking per-frame pose `let`s from the parent.
- Modify: `Sources/AirPostureMac/MenuBarView.swift` — pass `tracker.liveReadings` into the gauge; do **not** observe it; `ScrollView(.vertical)` + clip; only write `contentHeight` when it actually changes.
- Modify: `Tests/AirPostureAnalyticsStoreCheck/main.swift` — prove pose samples do not fire `tracker.objectWillChange`.
- Modify: `Tests/run-native-checks.sh` — compile `LivePostureReadings.swift` into the store/tracker check.
- Modify: `AirPostureMac.xcodeproj/project.pbxproj` — add the new file with the existing `A1…` / `A2…` ID pattern.
- Modify: `Tests/AirPostureUIFixture/main.swift` — vertical-only `ScrollView` on the isolated fixture pages (same overflow class).

Do not create a new SwiftPM test target.

---

### Task 1: Isolate live pose publications

**Files:**
- Create: `Sources/AirPostureMac/LivePostureReadings.swift`
- Modify: `Sources/AirPostureMac/PostureTrackingManager.swift`
- Modify: `Tests/AirPostureAnalyticsStoreCheck/main.swift`
- Modify: `Tests/run-native-checks.sh`
- Modify: `AirPostureMac.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing `PostureTrackingManager.handleMotion`, fixture `receiveFixture` in the store check, `PostureBand`, `DominantAxis`, `coachingCaption`, `slouchProgressClamped`.
- Produces:
  - `struct LivePostureSnapshot: Equatable` with the fields below.
  - `@MainActor final class LivePostureReadings: ObservableObject` with `let liveReadings` on the tracker (not `@Published` — the object identity is stable).
  - `func replace(_ snapshot: LivePostureSnapshot)` that no-ops when `==`.
  - Tracker public getters (`pitchDeltaDegrees`, `rollDeltaDegrees`, `yawDeltaDegrees`, `slouchProgress`, `isLookingAway`, `isSlouching`, `isPastThreshold`, `dominantAxis`, …) remain callable. They must not be `@Published`.
  - `postureBand` becomes a stored `@Published private(set)` value updated only when the resolved band changes (menu-bar icon still refreshes on upright / leaning / slouching / paused / waiting).

`LivePostureSnapshot` fields (exact names):

```swift
struct LivePostureSnapshot: Equatable {
    var pitchDeltaDegrees: Double = 0
    var rollDeltaDegrees: Double = 0
    var yawDeltaDegrees: Double = 0
    var dominantAxis: DominantAxis = .tilt
    var band: PostureBand = .waitingForHeadphones
    var slouchProgress: Double = 0
    var isCalibrated: Bool = false
    var caption: String = "Waiting for AirPods"
    var isLookingAway: Bool = false
}
```

`LivePostureReadings`:

```swift
#if SWIFT_PACKAGE
import AirPostureCore
#endif
import Combine
import Foundation

@MainActor
final class LivePostureReadings: ObservableObject {
    @Published private(set) var snapshot = LivePostureSnapshot()

    func replace(_ snapshot: LivePostureSnapshot) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
    }
}
```

On `PostureTrackingManager`:

```swift
let liveReadings = LivePostureReadings()
```

Do **not** mark `liveReadings` `@Published`.

- [ ] **Step 1: Write the failing publication test first**

Add `@MainActor private func checkLivePoseDoesNotInvalidateTracker()` to `Tests/AirPostureAnalyticsStoreCheck/main.swift` and call it from `main()` before the existing grace-restart test. Reuse the file’s `FixtureMotion` / `receiveFixture` helpers. Do not add a public test-only API on the tracker.

```swift
@MainActor
private func checkLivePoseDoesNotInvalidateTracker() {
    let suite = "AirPostureLivePoseCheck.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "isTrackingEnabled")
    defaults.set(0.0, forKey: "baselinePitchDegrees")
    defaults.set(0.0, forKey: "baselineRollDegrees")
    defaults.set(10.0, forKey: "sensitivityDegrees")
    var date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12))!
    var uptime = 100.0
    let tracker = PostureTrackingManager(
        defaults: defaults,
        now: { date },
        monotonic: { uptime },
        motionManager: nil
    )
    let settings = AirPostureSettings(defaults: defaults)
    tracker.configure(settings: settings)

    var trackerEvents = 0
    var liveEvents = 0
    let trackerSub = tracker.objectWillChange.sink { trackerEvents += 1 }
    let liveSub = tracker.liveReadings.objectWillChange.sink { liveEvents += 1 }
    defer {
        trackerSub.cancel()
        liveSub.cancel()
    }

    tracker.receiveFixture(FixtureMotion(pitch: -0.08, timestamp: uptime))
    let trackerAfterConnect = trackerEvents
    let liveAfterConnect = liveEvents
    check(liveAfterConnect >= 1, "first valid sample publishes live readings")
    check(tracker.connectionStatus == .connected, "first valid sample connects")
    check(tracker.postureBand == .upright, "small nod stays upright at 10° sensitivity")

    uptime += 0.05
    tracker.receiveFixture(FixtureMotion(pitch: -0.12, timestamp: uptime))
    uptime += 0.05
    tracker.receiveFixture(FixtureMotion(pitch: -0.16, timestamp: uptime))

    check(trackerEvents == trackerAfterConnect, "later upright pose samples must not publish PostureTrackingManager")
    check(liveEvents > liveAfterConnect, "later upright pose samples publish LivePostureReadings")
    check(tracker.pitchDeltaDegrees != 0, "tracker getters still expose the live tilt")

    let liveBeforeDisable = liveEvents
    tracker.isTrackingEnabled = false
    check(trackerEvents > trackerAfterConnect, "coarse chrome still publishes on Tracking toggle")
    check(tracker.postureBand == .paused, "disabling tracking publishes paused band")
}
```

Use a nod that stays inside the 10° tilt threshold after smoothing (`-0.08` … `-0.16` rad). If smoothing plus baseline ever trips `.leaning` in this fixture, shrink the pitches — the test is invalid if the band changes, because `postureBand` is allowed to publish.

- [ ] **Step 2: Run the store check and confirm the new assertion fails**

Run:

```bash
Tests/run-native-checks.sh store-check
```

Expected: compile may fail until `LivePostureReadings` exists (`liveReadings` missing), **or** it compiles against current `@Published` pose fields and fails with:

`FAIL later upright pose samples must not publish PostureTrackingManager`

Do not implement the split until you have seen one of those two failures.

- [ ] **Step 3: Add `LivePostureReadings.swift` and wire the Xcode / native-check build**

`Tests/run-native-checks.sh` `STORE_SOURCES` must include the new file. Current list is core `*.swift` plus settings, sound, alert, store, then the script concatenates `PostureTrackingManager.swift` with the test. After this task:

```bash
STORE_SOURCES=(
  "${CORE_SOURCES[@]}"
  Sources/AirPostureMac/AirPostureSettings.swift
  Sources/AirPostureMac/SoundPlayback.swift
  Sources/AirPostureMac/AlertService.swift
  Sources/AirPostureMac/WeeklyAnalyticsStore.swift
  Sources/AirPostureMac/LivePostureReadings.swift
)
```

In `AirPostureMac.xcodeproj/project.pbxproj`, add IDs that do not collide. Use:

- File ref: `A20000000000000000000029 /* LivePostureReadings.swift */`
- Build file: `A10000000000000000000029 /* LivePostureReadings.swift in Sources */`

Insert the file ref next to `PostureTrackingManager.swift` in the `AirPostureMac` group and in `PBXSourcesBuildPhase`.

SwiftPM needs no `Package.swift` change: the app target already compiles every file under `Sources/AirPostureMac`.

- [ ] **Step 4: Stop publishing IMU fields; sync a live snapshot instead**

In `PostureTrackingManager.swift`:

1. Remove `@Published` from these stored properties (keep the properties and their current access level):

   - `currentPitchDegrees`, `currentRollDegrees`, `currentYawDegrees`
   - `pitchDeltaDegrees`, `rollDeltaDegrees`, `yawDeltaDegrees`
   - `deviationDegrees`, `dominantAxis`
   - `isPastThreshold`, `isLookingAway`, `isSlouching`
   - `slouchElapsedSeconds`, `slouchProgress`

2. Convert `postureBand` from a computed property to:

   ```swift
   @Published private(set) var postureBand: PostureBand = .waitingForHeadphones
   ```

   Move the existing `switch` logic into `private func resolvedPostureBand() -> PostureBand` (same rules: paused / waiting / uncalibrated / slouching / leaning / upright).

3. Add one sync that every mutation path calls after it finishes updating fields:

   ```swift
   private func syncConsolePublications() {
       let nextBand = resolvedPostureBand()
       if postureBand != nextBand {
           postureBand = nextBand
       }
       liveReadings.replace(
           LivePostureSnapshot(
               pitchDeltaDegrees: pitchDeltaDegrees,
               rollDeltaDegrees: rollDeltaDegrees,
               yawDeltaDegrees: yawDeltaDegrees,
               dominantAxis: dominantAxis,
               band: nextBand,
               slouchProgress: slouchProgressClamped,
               isCalibrated: isCalibrated && connectionStatus == .connected,
               caption: coachingCaption,
               isLookingAway: isLookingAway
           )
       )
   }
   ```

   Call it from: the end of `init` (so a paused/disconnected launch does not stay on the stored `.waitingForHeadphones` default), the end of `handleMotion` (all paths that change pose, including error / nil / invalid / uncalibrated), `calibrate`, `applyActivePresetBaselines`, `stopMotionUpdates`, `handleHeadphonesConnected`, `handleHeadphonesDisconnected`, sleep observers, and `isTrackingEnabled.didSet` after start/stop. If `handleMotion` always syncs after `evaluatePosture`, do not also sync inside `evaluatePosture`. If a path returns before work, still sync when it cleared slouch or connection.

4. **Guarded chrome assigns.** `@Published` fires on assignment even when the value is unchanged. `handleMotion` currently does this every sample:

   ```swift
   lastErrorMessage = nil
   authorizationDenied = false
   connectionStatus = .connected
   ```

   Replace with compare-then-assign helpers used everywhere those three are set:

   ```swift
   private func setConnectionStatus(_ status: ConnectionStatus) {
       if connectionStatus != status { connectionStatus = status }
   }
   private func setLastErrorMessage(_ message: String?) {
       if lastErrorMessage != message { lastErrorMessage = message }
   }
   private func setAuthorizationDenied(_ denied: Bool) {
       if authorizationDenied != denied { authorizationDenied = denied }
   }
   ```

   Keep `@Published` on: `connectionStatus`, `isTrackingEnabled`, `sensitivityDegrees`, `gracePeriodSeconds`, `activePreset`, baselines, `didJustCalibrate`, `authorizationDenied`, `lastErrorMessage`, and the new stored `postureBand`.

5. Do not subscribe `MenuBarView` to `liveReadings` in this task. Gauge wiring is Task 2. After this task the store check must pass even though the UI still reads pose through `tracker` (that leftover is what Task 2 removes).

- [ ] **Step 5: Re-run the store check**

```bash
Tests/run-native-checks.sh store-check
```

Expected: `AirPosture analytics store checks passed` and no `FAIL live pose` lines. Existing grace / rejection assertions must still pass (`tracker.isSlouching`, `tracker.slouchProgress`, `tracker.slouchElapsedSeconds` remain readable).

---

### Task 2: Stop `MenuBarView` from reading live pose

**Files:**
- Modify: `Sources/AirPostureMac/PostureGaugeView.swift`
- Modify: `Sources/AirPostureMac/MenuBarView.swift`

**Interfaces:**
- Consumes: `tracker.liveReadings` (`LivePostureReadings`), `LivePostureSnapshot`, existing `PostureGaugeMapping.displayedPose`, `showTurnValue` / `showHeadTurn` from settings.
- Produces: `PostureGaugeView(readings:showTurnValue:showHeadTurn:)` — no pose `let`s from the parent.

- [ ] **Step 1: Change the gauge to observe live readings**

Replace the pose/band/caption parameters with:

```swift
struct PostureGaugeView: View {
    @ObservedObject var readings: LivePostureReadings
    let showTurnValue: Bool
    let showHeadTurn: Bool
```

Read `readings.snapshot` locally (a `private var snapshot` computed property is fine). Keep `displayedPose` / `displayedYaw` / `CoachChip` / accessibility as they are, sourced from the snapshot:

- `snapshot.pitchDeltaDegrees` / `rollDeltaDegrees` / `yawDeltaDegrees`
- `snapshot.dominantAxis`, `snapshot.band`, `snapshot.slouchProgress`
- `snapshot.isCalibrated`, `snapshot.caption`, `snapshot.isLookingAway`

`InstrumentBustView(...)` stays a child of the gauge and still takes value `pitch` / `roll` / `yaw` / `band`. Do not make the bust observe the tracker.

- [ ] **Step 2: Pass the object from `MenuBarView` without observing it**

`MenuBarView` must **not** declare `@ObservedObject` / `@EnvironmentObject` for `LivePostureReadings`. Passing a stable `let` on the tracker does not subscribe the parent.

Replace the current `PostureGaugeView(pitchDelta:…)` call with:

```swift
PostureGaugeView(
    readings: tracker.liveReadings,
    showTurnValue: settings.lookAwayGateEnabled || settings.showHeadTurnEnabled,
    showHeadTurn: settings.showHeadTurnEnabled
)
```

`MenuBarView` may still read coarse tracker chrome: `activePreset`, `connectionStatus`, `didJustCalibrate`, `canCalibrate`, `authorizationDenied`, `lastErrorMessage`, `isTrackingEnabled`, `sensitivityDegrees`, `gracePeriodSeconds`. It must not read `pitchDeltaDegrees`, `rollDeltaDegrees`, `yawDeltaDegrees`, `slouchProgress`, `dominantAxis`, `isLookingAway`, or `coachingCaption`.

`MenuBarIcon` stays `@ObservedObject var tracker`. After Task 1 it only invalidates on published chrome (connection, band, settings). Do not point the icon at `liveReadings` (that would rasterize the status image at IMU rate again). Lean-hint rotation then updates on band changes, not every sample — that is intended.

- [ ] **Step 3: Compile the app target**

```bash
./build.sh debug
```

Expected: build succeeds. `PostureGaugeView(` should have exactly one call site (`MenuBarView`).

---

### Task 3: Vertical-only popover scroll

**Files:**
- Modify: `Sources/AirPostureMac/MenuBarView.swift`
- Modify: `Tests/AirPostureUIFixture/main.swift`

**Interfaces:**
- Consumes: existing `ConsoleHeightKey` / `contentHeight` / `visibleScreenHeight`.
- Produces: a `ScrollView` that cannot pan on X; window height still tracks content up to the visible screen.

On macOS, `ScrollView { }` is both axes. Combined with any child intrinsic width > 360 (Charts, large ColorSelector, coach-chip `HStack`), two-finger left/right moves the document. That is the odd behavior.

- [ ] **Step 1: Lock the console scroll view to vertical and clip overflow**

In `MenuBarView.body` replace `ScrollView {` with:

```swift
ScrollView(.vertical, showsIndicators: true) {
    content
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ConsoleHeightKey.self, value: proxy.size.height)
        })
}
.scrollDisabled(false)
.clipped()
.frame(width: 360, height: min(contentHeight, visibleScreenHeight))
```

Keep width **360**. Do not wrap this in a second `ScrollView`.

Write height state only when it changes, so preference churn cannot resize the `MenuBarExtra` window during a flick:

```swift
.onPreferenceChange(ConsoleHeightKey.self) { height in
    if abs(height - contentHeight) > 0.5 {
        contentHeight = height
    }
}
```

Keep `content`’s `.padding(16).frame(width: 360)` so the document width is exactly the clip width. If a child still reports a larger min width, `.clipped()` plus `.vertical` must prevent X translation.

- [ ] **Step 2: Same axis on fixture-only pages**

In `Tests/AirPostureUIFixture/main.swift`, change the Reminders / Analytics hosts from `ScrollView {` to `ScrollView(.vertical) {`. The Console page uses `MenuBarView` and inherits Task 3 Step 1.

- [ ] **Step 3: Build the UI fixture**

```bash
Tests/AirPostureUIFixture/build.sh
```

Expected: fixture builds. This does not prove trackpad behavior; that is Task 4.

---

### Task 4: Verify

**Files:** none unless a check failed.

- [ ] **Step 1: Run the automated suite**

```bash
make test
```

Expected: `AirPostureFeatureCheck` / `AirPostureMappingCheck` / `AirPostureBustCheck` pass; native settings, sound, and store checks pass. The new live-pose assertions pass. Intentional sound/store diagnostic lines are expected.

- [ ] **Step 2: Build Debug and confirm the only call site**

```bash
./build.sh debug
rg -n "PostureGaugeView\\(" Sources Tests
```

Expected: production call only in `MenuBarView.swift`. No `pitchDelta: tracker.` in `MenuBarView.swift`.

- [ ] **Step 3: Human native QA (required; do not mark the plan done without reporting this)**

Launch the real app (`make run` or the Debug `.app`). With Tracking **on** and AirPods connected:

1. Open the popover. Expand **This week** and **Options** so the console is taller than the screen.
2. Two-finger scroll vertically — it must feel as smooth as Tracking paused. The bust and coach chip may still animate; the *scroll document* must not hitch.
3. Two-finger swipe left/right — the document must not move on X. Rubber-banding only on Y, if any.
4. Collapse / expand disclosures; calibration, snooze, sound preview, and color picker still work.
5. Turn Tracking off, then on: scroll remains vertical-only; hero resumes live pose.

If Step 3.2 is still hitchy, the first thing to re-check is whether `MenuBarView` still observes `liveReadings` or still assigns a `@Published` tracker field every sample (`connectionStatus = .connected` without a guard). Do not start SceneKit or chart refactors.

---

## Out of scope

- SceneKit `antialiasingMode`, `preferredFramesPerSecond`, clip-view `updatePlayback` observers.
- `@Observable` migration.
- Throttling IMU in Core Motion.
- Virtualizing Options / Charts.
- Changing week-store 1 Hz sampling.
- Menu-bar icon lean-hint animation at IMU rate.
- Commits and PRs.

## Self-review

- Lag: Task 1 removes IMU `@Published` on the object `MenuBarView` holds; Task 2 stops the parent from reading live fields. Both are required (`ObservableObject` is all-or-nothing per object, and `connectionStatus = .connected` every sample would reintroduce the hitch even after the split).
- Horizontal scroll: Task 3.
- Overlay/tests: getters preserved; store check extended, not replaced.
- No placeholders. No “similar to Task N” omissions.
- Names are consistent: `liveReadings`, `LivePostureSnapshot`, `replace(_:)`, `syncConsolePublications()`, `resolvedPostureBand()`.
