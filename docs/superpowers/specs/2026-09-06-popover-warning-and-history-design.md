# Popover warnings, sound selection, and posture history

Date: 2026-09-06

Status: The user approved the proposed design in chat. This document specifies that design for the written-spec review required by the requested brainstorming workflow.

## 1. Outcome and working constraints

AirPosture should give a gentle visual cue before the user crosses their sensitivity boundary, make overlay appearance adjustable, reliably play the selected sound, and explain posture patterns through detailed weekly bars and longer-term history.

The early cue is visual only. The user explicitly approved retaining the existing countdown and sound triggers.

Work directly on main. Do not create a branch, commit, or start a dev server. Preserve the pre-existing .gitignore change. This document remains uncommitted. Implementation follows review of this written spec and preparation of the implementation plan.

Keep the existing native macOS menu-bar application, sculptural posture view, calibration presets, and local storage. This design supersedes the warning timing, appearance settings, sound controls, and analytics portions of the earlier console specification where they differ.

## 2. Evidence from the current application

- The overlay currently requires sustained slouching, so it cannot appear before the sensitivity boundary or during the grace countdown.
- Overlay strength has a 20% minimum, a 70% registered default, and one shared value for every style. The visual ramp is fixed at eight seconds.
- The blur material is enabled at full visibility while only its tint responds to strength. Lowering the existing slider therefore does not directly reduce the blur effect.
- Sound selection is passed to AlertService. All five system audio files exist and have the same stereo, 48 kHz, 24-bit PCM AIFF format. The root cause of the reported failure is not yet established. The current player ignores preparation and playback success values.
- Historical records contain monitored seconds, off-neutral seconds, and episode counts. They cannot retrospectively distinguish countdown from sustained slouching.
- The app has both SwiftPM and Xcode build paths. Dependency and source-file integration must support both.

## 3. Early visual warning

### Settings

| Control | Default | Range or behavior |
| --- | --- | --- |
| Early visual cue | On | Off restores overlay activation after grace; scoring is identical in both modes. |
| Start cue at | 70% of sensitivity | 10–100%, in 5-point increments. Enabled when the early cue is on. |
| Fade-in | 3 seconds | 0.5–10 seconds, in 0.5-second increments. |
| Max strength | 5% for Blur; 70% for other styles on a fresh install | 5–100%, stored separately for each visible style. |

The start control is relative to the existing combined tilt/lean sensitivity ellipse. It is not a second independent angle threshold. At the default 10-degree tilt limit, a pure forward tilt begins the cue above approximately 7 degrees. Combined tilt and lean use the same normalized deviation as detection.

### Posture states and intensity

Let r be normalized deviation: zero at neutral and one at the existing sensitivity boundary. Let a be the configured cue-start fraction. Let g be elapsed grace divided by grace duration, clamped to zero through one. All inputs must be finite and clamped to their valid domains before use. Smoothstep(u) means u × u × (3 − 2 × u), with u clamped to zero through one.

When the early cue is on:

1. Below the real sensitivity boundary, at or below a, the intensity target is zero.
2. Between a and one, the target increases smoothly from zero to 25% of the selected maximum. Use a smoothstep curve over that interval. A steady small lean therefore remains a small cue even after a long hold.
3. At the sensitivity boundary and during countdown, the target is 25% plus 75% times smoothstep(g), multiplied by the selected maximum.
4. After grace, the target is the selected maximum.
5. When a is one, omit the pre-threshold interval; countdown begins with the same 25% target and smooth fade-in.

When the early cue is off, the target remains zero until sustained slouching, then becomes the selected maximum. The configured fade-in still applies.

Use a continuous time-based approach toward the target. Define the fade-in value as the time to reach 95% of a held target. An exponential response with time constant fadeIn / ln(20) provides frame-rate-independent behavior without restarting an animation on each motion sample. For a lower positive target, use the same response with a 350 ms time to reach 95% of the change. When the target becomes zero, fade from the current rendered strength to exactly zero over 350 ms and remove the panels; do not leave an asymptotic residual visible. Reduce Motion snaps directly to the appropriate target, including the pre-threshold cap.

The early cue must never start the grace timer, set isPastThreshold or isSlouching, increment an episode, trigger a sound/banner, or change the menu-bar warning state. Time below the real sensitivity boundary continues to count as within sensitivity.

### Eligibility and dismissal

Only show cues while tracking is enabled, the headphones are connected, the active preset is calibrated, the look-away gate is inactive, snooze is inactive, and the selected warning style is not Off.

Tracking disablement, disconnect, calibration/preset transitions, look-away gating, snooze, and Off immediately cancel stale overlay state. Returning toward neutral fades the cue to zero. Resume recomputes from current posture; it does not replay an old ramp. Escape continues to snooze any visible warning overlay.

Sound/banner timing remains at one grace period, or two when the existing delayed-sound option is enabled. The 45-second warning cooldown remains intact.

## 4. Overlay strength and color

Each of Glow, Border, Dim, and Blur remembers its maximum strength and color. Switching styles restores that style's saved values. Off does not overwrite appearance preferences.

Use the external [ColorSelector package](https://github.com/jaywcjlove/ColorSelector) for the color control. Its [package manifest](https://raw.githubusercontent.com/jaywcjlove/ColorSelector/main/Package.swift) targets macOS 14 and requires Swift 6.1; the inspected local toolchain is Swift 6.3.3. Resolve a compatible immutable release or revision and retain the resolved dependency information in both build paths.

The picker presents a color swatch and customizable color selection inside the popover. Keep Warm, Cool, and Alert as convenient preset swatches, alongside the custom selection. Hide alpha controls: color and maximum strength are separate settings. Persist colors as validated opaque sRGB components. Invalid stored colors fall back to Warm. The external package must actually render the picker; a native-only substitute does not satisfy this requirement.

Add a reset action for the active style's appearance. Blur resets to 5%; other styles reset to 70%; colors reset to Warm.

### Migration

When no new per-style preference exists:

- Initialize Glow, Border, and Dim from the previously persisted global maximum, clamped to the new range, or 70% when none was saved.
- Initialize Blur to 5%. The old global value did not represent blur visibility and is not imported as its new default.
- Initialize each style's color from the old Warm/Cool/Alert selection, or Warm when absent.
- Once per-style values exist, never overwrite them during future launches or migrations.

### Rendering

Strength must affect the entire visible effect. At zero intensity, no style may leave a visible baseline tint, border, dim layer, or blur. Every effect must grow monotonically with strength.

For Blur, scale the public NSVisualEffectView's actual visibility, not only a tint drawn above it. Five percent represents a low-opacity blend of the supported system blur effect, not a claim about a blur radius. Preserve public APIs and the existing click-through, non-activating panels on all displays.

Reduce Transparency maps Glow and Blur to Dim using the selected source style's color and strength. Accessibility contrast adjustments must remain bounded by the intensity envelope so the early cue can still disappear completely.

## 5. Sound playback and preview

The required outcome is that Pop, Tink, Purr, Bottle, and Morse each play their own selected sound at the chosen volume, both from a preview and from a real eligible posture warning.

The implementation begins by reproducing the failure and tracing selection, persistence, selected asset, preparation, playback result, and audio output route. Do not assume that Pop is hardcoded or that the files are missing; current evidence contradicts those simple explanations.

Add an explicit Preview button next to the sound selection. Preview uses the same sound-loading and playback service as real warnings, accepts the currently selected pack and volume, and works without headphones, calibration, or a posture violation. A user-initiated preview may play while monitoring is snoozed. It never posts a notification, creates an episode, or consumes/resets the warning cooldown.

Keep the active player alive for the full clip. Starting another preview stops the prior preview. Ensure preparation failure, a false playback return value, thrown errors, and asynchronous decode failure are handled rather than silently counted as successful playback.

Use the selected system sound file first and the selected sound's NSSound fallback when needed. Never substitute Pop for a failed pack. If both paths fail, display a concise inline error in Reminders, including the selected sound's name, and clear it after a successful playback. Keep useful technical diagnostics in the development logs.

Retain the optional softer sit-up chime and its existing independence from the warning cooldown. Real warnings continue to obey snooze, delayed sound, cooldown, and existing Focus banner behavior.

## 6. Weekly stacked bars and details

Keep the existing compact weekly metrics. Expanding the analytics area reveals Monday–Sunday bars with a shared 0–100% scale. Each day with monitored time has a full-height stack:

| Segment | Definition |
| --- | --- |
| Green — Within sensitivity | Eligible monitored time below the actual threshold. Early visual cue time belongs here. |
| Orange — Countdown | Eligible time at or beyond the actual threshold before grace expires. |
| Red — Sustained slouch | Eligible time at or beyond the actual threshold once grace has expired. |
| Neutral gray — Earlier off-neutral, unsplit | Older recorded off-neutral time whose countdown/slouch split is unavailable. |

The existing look-away behavior remains compatible: gated time is monitored but does not score as off-neutral. Describe the metric as time within the configured sensitivity rule, not as an independent medical assessment of posture.

Show an empty marker for days without monitored time. Future days remain empty. Highlight today without changing category colors. A legend names each category; include the unsplit legend only when it is present in the displayed data.

Hovering or selecting a day reveals a bounded detail card containing:

- Full weekday and date; mark today as in progress.
- Total monitored duration.
- Duration and percentage for each available segment.
- Slouch episode count.
- A short explanation when older off-neutral time is unsplit.

Use a consistent duration formatter with seconds available for short recordings, rather than rounding a short nonzero interval to zero minutes. Calculate proportions from unrounded durations. Provide the same information through accessibility labels and keyboard selection; hover cannot be the only way to access it.

## 7. Historical trend

Below the expanded weekly chart, provide a compact history chart with 7, 30, and 90-day controls; default to 30 days. These are inclusive local-calendar ranges ending today.

Plot daily upright percentage on a fixed 0–100% vertical scale. Add a visually distinct seven-day trailing trend, weighted by monitored duration:

upright percentage = 100 × (monitored seconds − off-neutral seconds) / monitored seconds.

The trend sums the numerator and denominator over the seven calendar days ending at each plotted date. It does not average daily percentages equally. Existing legacy records can participate because their monitored and off-neutral totals are known.

Dates with no monitored time have no daily point. Break both line series across those missing dates rather than implying a measured value or drawing an uninterrupted improvement through a gap. A day's trailing trend can use observed days in its trailing window, with its evidence coverage shown in the detail card. Only produce a trend value where that day has monitored time and at least two distinct dates in the trailing window contain observations.

Selecting a date shows its exact percentage, monitored duration, and trailing trend when available, including the observed-day count and monitored duration behind that trend.

A numeric comparison summarizes the latest seven days against the preceding seven days when both windows contain monitored time. Use the weighted percentages and state the change in percentage points. Show the duration and observed-day coverage for both windows in its detail text. Otherwise show that more history is needed. Do not label sparse observations as proof of improvement or regression.

Include the concise explanatory text: “Higher means more time within your sensitivity settings.” This keeps changes in sensitivity and monitoring coverage visible as limits on interpretation. Historical comparisons are descriptive, not a causal claim about health or the app's effectiveness.

## 8. Analytics storage and time accounting

Retain the local weekly-analytics.json location and 90-day history policy. Introduce schema version 2 with daily fields for monitoredSeconds, offNeutralSeconds, countdownSeconds, slouchSeconds, and slouchEpisodes. Duration fields support fractional seconds; episode counts remain integers.

Decode schema 1 duration values without loss. Missing countdownSeconds and slouchSeconds decode as zero. Derive the unsplit legacy remainder as offNeutralSeconds minus countdownSeconds minus slouchSeconds. Thus older time remains visibly unsplit even when new samples are added to the same day.

For every day, enforce these invariants:

- All durations are finite and nonnegative.
- Off-neutral time does not exceed monitored time.
- Countdown plus sustained slouch time does not exceed off-neutral time.
- Within-sensitivity, countdown, sustained slouch, and unsplit durations sum to monitored time.
- Each transition into sustained slouching produces at most one episode.

Reject inconsistent or unsupported future documents without silently overwriting them. Preserve the existing corrupt-file quarantine behavior and an actionable inline storage-error message. Save valid updates atomically.

Accumulate elapsed eligible time rather than assuming every delayed timer tick represents exactly one second. Account for state transitions, split intervals at local midnight, and exclude sleep, disconnected time, disabled tracking, and uncalibrated time. Monotonic elapsed time supplies duration; local calendar dates assign buckets. Close the active interval on sleep and state transitions, and begin a fresh interval after wake or reconnect. Do not backfill suspended execution as posture evidence.

Keep the periodic flush and termination flush. A failed disk write must preserve in-memory totals and allow later retry. Calendar-based pruning keeps today and the preceding 89 local dates, matching the 90-day display range.

## 9. Component boundaries and popover layout

- AirPostureSettings owns validated persisted preferences and appearance migration.
- PostureTrackingManager supplies a consistent pose/scoring snapshot, including normalized deviation and eligibility. It remains the authority for grace and sustained-slouch transitions.
- A pure warning-intensity model in AirPostureCore maps that snapshot and settings to an intensity target and time-based response. WarningOverlayManager owns only panel lifecycle and rendering.
- AlertService owns shared playback and warning policy. Extract a focused audio player if needed to make selection and failure behavior observable and testable.
- Pure analytics models in AirPostureCore own duration classification, date buckets, legacy migration, percentages, and history projections. WeeklyAnalyticsStore owns live accumulation and file persistence.
- Dedicated analytics and appearance/reminder view components keep the existing large MenuBarView from absorbing all new chart and picker logic.

The popover remains the primary interface. Retain the hero posture view, compact weekly summary, presets, calibration, and grouped Options. Place early-cue timing and active-style strength/color together under visual reminders; keep sound and its Preview adjacent. Disable irrelevant controls while the style is Off without erasing their values.

Keep charts inside the expanded analytics area so the collapsed console stays compact. Bound the popover to the current screen's visible height and make expanded content scrollable. Opening both analytics and Options must not hide calibration, dismiss controls, or the lower settings off-screen. The color picker and chart details must stay usable near screen edges and in both light and dark appearance.

## 10. Verification and completion evidence

### Detection and overlays

- Check intensity at neutral, just below/above cue onset, just below/at the real boundary, through grace, and after sustained slouching.
- Verify the onset-at-100% edge case, early-cue disabled behavior, non-finite input handling, and time-based fade behavior at different tick rates.
- Prove that the early cue does not alter scoring, grace, episodes, warning cooldown, or sound triggers.
- Verify immediate suppression for snooze, look-away, disconnect, calibration/preset changes, tracking off, and style Off, plus recovery and accessibility behavior.
- Visually inspect actual native overlays at low/high strength. In particular, 5% Blur must visibly preserve much more underlying clarity than 100% Blur, and zero must leave no effect.

### Settings and dependency

- Verify per-style strength/color restoration, reset, persistence across launches, and one-time legacy migration, including Blur's 5% default.
- Verify the external ColorSelector renders, accepts custom colors, and remains usable inside the menu-bar popover.
- Build both supported paths when their tools are available. At minimum, compile and assemble the real SwiftPM app bundle and validate the Xcode project's dependency/source wiring. Explicitly report any unavailable Xcode build verification.

### Sound

- Record a reproducible failure or precise diagnostic evidence before applying its corrective change.
- Exercise all five selected sounds through preview and the real-warning playback path, including selected-file identity, retained lifetime, success/failure reporting, and chosen volume.
- Verify preview does not modify warning cooldown, banner state, or analytics, and that real-warning snooze/delay policy remains intact.
- Audible playback is a runtime acceptance criterion; a successful file lookup or mocked unit test alone is insufficient.

### Analytics and UI

- Verify category conservation, grace-to-slouch transitions, early-cue classification, episode edges, and exclusion of ineligible time.
- Verify elapsed-time accounting across timer delays, midnight, sleep/wake, reconnect, and local calendar/DST boundaries.
- Round-trip schema 2; load schema 1 and mixed legacy/new days without inventing splits or losing totals; verify corruption and write-failure handling.
- Verify weighted trend and comparison math, empty ranges, missing-day gaps, partial today, and 90-day pruning.
- Inspect a real rendered popover with empty, mixed, historical, and dense data; verify hover/click/keyboard details, legends, both appearance modes, and maximum expanded height.
- Run the existing mapping checks and new focused checks for the changed behavior. Update the README's controls and metric descriptions to match the delivered behavior.

The goal is complete only when all requested features are implemented and the evidence above supports their behavior. A design document or a successful build by itself does not complete the goal.
