# Popover Warning and History Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task by task. Work and review uncommitted diffs; the user's prohibition on commits and branches overrides the skill's git workflow.

**Goal:** Deliver the approved early overlay, per-style appearance, reliable sound selection, stacked posture bars, and historical trend in the native popover.

**Architecture:** Keep motion scoring authoritative in PostureTrackingManager. Put deterministic warning and analytics calculations in AirPostureCore, native side effects in focused services, and expanded chart/settings UI in separate SwiftUI components.

**Tech Stack:** Swift 6.3 toolchain, macOS 14+, SwiftUI, AppKit, AVFoundation, Swift Charts, external ColorSelector through SwiftPM.

**Spec:** ../specs/2026-09-06-popover-warning-and-history-design.md

## Global Constraints

- Work directly on main. Do not create a branch, commit, or start a dev server.
- Preserve the pre-existing .gitignore modification.
- The early cue is visual only; existing scoring, grace, audio delay, and 45-second warning cooldown remain intact.
- Start cue at 70% by default, range 10–100%; fade-in 3 seconds by default, range 0.5–10 seconds.
- Maximum strength is 5–100%, stored per style; Blur initializes/resets to 5%, other styles to 70% unless migrated.
- Use ColorSelector to render the custom picker. Support both SwiftPM and Xcode builds.
- Keep local storage and exactly 90 inclusive local-calendar days. Preserve legacy totals and label unsplit time.
- Run focused tests first, then the existing checks and actual native runtime verification. Never claim audible or visual verification from mocks alone.

The installed Command Line Tools lack a working XCTest/Testing framework. Use the existing executable-check pattern with plain assertion helpers and failing exit codes. Verification on this Mac works with a clean temporary module cache and the default SDK; SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk is a verified fallback. This is a test-runner adaptation; all acceptance cases remain required.

## File structure

Create core WarningIntensity.swift and PostureAnalytics.swift for deterministic models. Extend AirPostureSettings.swift and WarningOverlayManager.swift for appearance and cue rendering. Replace the local analytics math in WeeklyAnalyticsStore.swift with the core models, retaining the native store there. Add PostureAnalyticsView.swift and ReminderOptionsView.swift for focused UI. Add SoundPlayback.swift if playback isolation is needed. Add an AirPostureFeatureCheck executable check target and focused native verification utilities under Tests. Update Package.swift, Xcode wiring, build.sh when dependency resources require it, and README.md.

### Task 1: Warning model, appearance preferences, and native overlay

**Files:** Create Sources/AirPostureCore/WarningIntensity.swift and Tests/AirPostureFeatureCheck/WarningIntensityChecks.swift. Modify Sources/AirPostureMac/AirPostureSettings.swift, WarningOverlayManager.swift, and PostureTrackingManager.swift only for a normalized-deviation accessor. Add the SwiftPM executable check target in Package.swift. Keep existing settings properties callable until Task 4 replaces their UI.

**Interfaces:** Produce public WarningIntensity.target(deviation:graceProgress:isSlouching:earlyEnabled:onset:) -> Double returning a unit fraction; public WarningEnvelope with update(target:elapsed:fadeIn:reduceMotion:) -> Double and reset(). Settings exposes earlyCueEnabled, cueStartFraction, overlayFadeInSeconds, active-style maxOverlayStrength and overlayColor, plus resetOverlayAppearance(). Store colors as a public Codable sRGB value type with red, green, blue components. Tracker exposes normalizedDeviation: Double.

- [x] Add the SwiftPM executable check target and tests with hand-derived expectations:

```swift
expectEqual(WarningIntensity.target(deviation: 0.7, graceProgress: 0, isSlouching: false, earlyEnabled: true, onset: 0.7), 0)
expectEqual(WarningIntensity.target(deviation: 0.85, graceProgress: 0, isSlouching: false, earlyEnabled: true, onset: 0.7), 0.125, accuracy: 0.0001)
expectEqual(WarningIntensity.target(deviation: 1, graceProgress: 0.5, isSlouching: false, earlyEnabled: true, onset: 1), 0.625)
```

- [x] Run swift run --disable-sandbox AirPostureFeatureCheck warnings and record the expected missing-feature failure. Implement the stage mapping, finite validation, onset-at-one edge case, time-based envelope, exact 350 ms fade to zero, and Reduce Motion behavior. Add frame-rate independence and recovery tests with literal expectations such as 0.95 after 3 seconds toward a unit target.
- [x] Persist per-style color and strength, migrate legacy non-blur strength and tint, initialize Blur at 0.05, and clamp/validate all new fields. Verify with isolated UserDefaults suites that switching styles and reloading restores each color/strength and never repeats migration.
- [x] Replace the fixed overlay ramp with the tested model. Derive eligibility from tracking, connection, calibration, look-away, snooze, and style. Cancel stale panels for ineligible state; scale actual blur visibility and remove baseline alpha at zero for every style. Preserve Escape and accessibility behavior.
- [x] Run the focused tests, existing mapping checks, and a SwiftPM build. Report exact results and any runtime-only verification still pending. Do not change playback, analytics, or the settings UI.

### Task 2: Classified duration storage and history projections

**Files:** Create Sources/AirPostureCore/PostureAnalytics.swift and Tests/AirPostureFeatureCheck/PostureAnalyticsChecks.swift. Modify WeeklyAnalyticsStore.swift and PostureTrackingManager.swift for consistent scoring-state notifications.

**Interfaces:** Produce public DayBucket (Double monitoredSeconds, offNeutralSeconds, countdownSeconds, slouchSeconds; Int slouchEpisodes), public AnalyticsState (.inactive, .upright, .countdown, .slouch), public DayAnalytics (date and bucket, percentages/segment durations), and public HistoryPoint (date, dailyPercent, trendPercent, trendMonitoredSeconds, trendObservedDays, segment ID for gaps). Preserve WeekSummary's existing UI-facing properties; add dailyDetails: [DayAnalytics]. Store exposes history(days: Int) -> [HistoryPoint] and a latest-seven versus previous-seven comparison with coverage. Use a consistent tracker scoring snapshot/event, not separately observed pre-mutation Published fields.

- [x] Write real core tests for legacy migration, category conservation, weighting, missing days, and interval splitting. Fixture: decode {"monitoredSeconds":100,"offNeutralSeconds":40,"slouchEpisodes":2}; expect upright 60, legacy unsplit 40, countdown 0, slouch 0. Fixture: 60 upright seconds on day one and 540 off-neutral seconds on day two; expect a 10% weighted trend, not 50%.

```swift
let bucket = try JSONDecoder().decode(DayBucket.self, from: Data(#"{"monitoredSeconds":100,"offNeutralSeconds":40,"slouchEpisodes":2}"#.utf8))
expectEqual(bucket.unsplitSeconds, 40)
expectEqual(bucket.uprightSeconds, 60)
```

- [x] Observe the failing tests, then implement validated schema-1/schema-2 decoding, derived unsplit remainder, calendar helpers, weighted history, contiguous series segmentation, period comparison, and 90-day pruning. Reject malformed durations and unsupported versions without destroying the original document.
- [x] Account elapsed time using monotonic timestamps and consistent scoring states, split at midnight, exclude sleep and ineligible time, count only transitions into sustained slouch, and resume without backfilling. Cover midnight, DST, pause/reconnect, and same-day legacy-plus-new data.
- [x] Integrate the core accumulator with the native store's periodic/termination flush and sleep/wake notifications. Preserve in-memory data through atomic-write failures, surface errors, and clear errors after successful recovery. Publish chart summaries from actual data.
- [x] Run focused analytics tests and compile the application. Preserve existing summary consumers until the new views arrive. Report interfaces and evidence in the task report.

### Task 3: Sound diagnosis and shared preview playback

**Files:** Modify AlertService.swift; create SoundPlayback.swift and native test/probe utilities under Tests if needed. Add an observable sound-error property accessible to the reminder view. Do not edit MenuBarView.swift in this task.

**Interfaces:** AlertService.shared.previewSound(pack: SoundPack, volume: Double), observable lastPlaybackError: String?, and the existing warning/chime entry points. The preview and warnings use the same selected-asset playback service.

- [x] Reproduce all five current packs through the actual playback API and inspect prepare/play results, selected path, persistent preference, player lifetime, audio route, and runtime version. Preserve a diagnostic transcript. Do not assume a missing file or hardcoded Pop: those explanations have already been ruled out by source/file inspection.
- [x] Write a failing regression covering the confirmed failure. At minimum exercise actual selected-asset loading and false preparation/playback handling at the audio boundary; a mock that always succeeds is insufficient.

```swift
for pack in SoundPack.allCases {
    let player = try AVAudioPlayer(contentsOf: pack.systemSoundURL)
    print(pack.rawValue, player.duration, player.prepareToPlay())
}
```

- [x] Correct the observed cause and retain each player through completion. Handle thrown, false-return, and asynchronous decode failures, then attempt NSSound with the same selected name. If both fail, set an inline error naming the pack; successful playback clears the error. A second preview replaces the first.
- [x] Add preview without consuming warning cooldown, posting banners, or touching analytics. Keep real warning snooze/double-grace/Focus policy, volume, and recovery-chime behavior intact.
- [x] Exercise every sound and verify the real-warning path, selected-file identity, preview independence, and error recovery. Clearly distinguish playback API results from audibility; leave any necessary physical listening check explicit for final runtime verification.

### Task 4: ColorSelector, controls, stacked bars, and history UI

**Files:** Create ReminderOptionsView.swift and PostureAnalyticsView.swift. Modify MenuBarView.swift, AirPostureMacApp.swift as needed, Package.swift, AirPostureMac.xcodeproj/project.pbxproj, and build.sh only if dependency resources need packaging.

**Interfaces:** Consume Task 1 settings and warning accessors, Task 2 analytics/history models, and Task 3 preview/error API. Render ReminderOptionsView(settings:) and PostureAnalyticsView(store:isExpanded:) in the existing console.

- [x] Resolve ColorSelector to an immutable compatible release/revision; inspect its actual public API and resources. Add the external product to both native build paths and preserve resolved dependency metadata.

```swift
ColorSelector(selection: colorBinding).showsAlpha(false)
Button { AlertService.shared.previewSound(pack: settings.soundPack, volume: settings.soundVolume) } label: {
    Label("Preview", systemImage: "play.fill")
}
```

- [x] Build grouped controls for early cue, onset, fade-in, active-style maximum, preset swatches, custom color, reset, sound pack, preview, volume, and delayed sound. Show effective percentage/duration values and inline playback failures. Disable irrelevant controls for Off without erasing settings.
- [x] Render 100% daily stacks with green/orange/red/legacy-gray segments, empty days, today indicator, and an appropriate legend. Add bounded hover/click details containing full date, monitored duration, each segment duration/percentage, episode count, and legacy explanation. Provide keyboard and accessibility access to the same content.
- [x] Render daily and duration-weighted trend lines on a fixed 0–100 scale with 7/30/90 controls (30 default), observed-data gaps, date details, weighted period comparison with coverage, and the explanatory sensitivity caption. Use Swift Charts; no charting dependency is required.
- [x] Bound the native popover's height to the current visible screen, retain the hero and compact summaries, and keep both expanded analytics and Options reachable by scrolling. Compile the real app and inspect screenshots for light/dark, empty/mixed/dense history, tooltips, and the external picker near screen edges.

### Task 5: Integrated verification, documentation, and review

**Files:** Update README.md, any focused tests or production files with confirmed integration defects, and this plan's progress record.

- [x] Run swift run --disable-sandbox AirPostureFeatureCheck, swift run --disable-sandbox AirPostureMappingCheck, and ./build.sh debug. Run xcodebuild when installed; otherwise validate project wiring and explicitly report the unavailable build path.
- [ ] Launch only the assembled .app for native QA. Verify actual low/high-strength overlays, all sounds, persistence, tooltip/keyboard behavior, history gaps, maximum expanded popover height, and setting changes. Use temporary fixtures or test utilities without replacing the user's persisted analytics/preferences.
- [x] Correct failures with focused regression tests and rerun only affected checks before the final integrated pass.
- [x] Update README control defaults, custom color behavior, early cue/scoring relationship, sound preview, chart definitions, data migration, retention, and build requirements.
- [x] Review the complete uncommitted diff against every spec acceptance item. Keep all changes uncommitted on main; report evidence and any real remaining verification limitations without claiming the goal complete prematurely.

## Delivered verification status

Implementation and independent reviews are complete, including final corrections for shared native fallback sound ownership and rejected-motion episode counting. Final `make test`, `./build.sh debug`, and strict bundle signature verification pass. The SwiftPM debug app is assembled at `.build/arm64-apple-macosx/debug/AirPosture.app`. Xcode source/resource/dependency wiring was validated; actual Xcode is unavailable on this CLT-only host. Work remains uncommitted on main.

The native-QA checklist remains partially open: production views were exercised in an isolated ordinary-window fixture, all five real selected assets completed native preview/warning playback callbacks, and settings persisted through relaunch. Physical audibility and the original Pop-only symptom, actual MenuBarExtra edge placement, physical headphone/motion lifecycle, multiple displays, global Escape permissions, accessibility preference transitions, and underlying-background Blur clarity were not fully established. These limits do not invalidate the passing automated/model/native-boundary checks, but the full runtime acceptance goal is not claimed complete.

Detailed reports are retained under `.superpowers/sdd/2026-09-06-popover-warning-and-history/` because this work is intentionally uncommitted. See `acceptance.md`, `task-4-native-qa.md`, `final-fix-report.md`, and `final-re-review.md`.
