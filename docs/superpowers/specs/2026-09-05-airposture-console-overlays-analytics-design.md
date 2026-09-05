# AirPosture console, overlays, and weekly analytics

Design spec for the next AirPosture Mac slice. Implementation must follow this document; do not invent extra windows, private blur APIs, or Screen Recording.

**Status:** approved  
**Date:** 2026-09-05  
**Platform:** macOS 14+, SwiftUI `MenuBarExtra` with `.window` style, accessory app (`LSUIElement` + `NSApp.setActivationPolicy(.accessory)`)  
**Bundle ID:** `com.macposture.airposture`

---

## Problem

AirPosture already detects tilt and lean from AirPods IMU, waits through a grace period, then fires a Pop sound and a “Sit up straight!” banner (`AlertService.nudgeIfAllowed()`, 45s throttle). The popover is a 320pt settings panel with a small 2-axis gauge.

That is easy to miss. A slouch while looking at a full-screen display should tint the *screen*, not open another window. The popover should feel like a cockpit (live attitude + this week), not a preference form. Users need a week-scale answer to “am I sitting better?” without a stats window or a session database.

Constraints that stay non-negotiable:

- Menu-bar only. No Dock icon, no extra HUD/stats window, no blocking overlay that traps clicks.
- Public AppKit / SwiftUI / AVFoundation / UserNotifications / Intents only.
- Motion data never leaves the Mac.

---

## Decisions

These are locked. If a later idea conflicts with this list, this list wins.

1. **One overlay manager + one local week store + one richer popover.** Three objects, not a window zoo.
2. **Overlays are additive.** Keep today’s Pop + banner path. Overlays and extra sounds sit beside it; they do not replace the existing nudge unless the user turns a piece off.
3. **Default overlay is Glow/vignette.** Click-through, one `NSPanel` per `NSScreen`.
4. **Style picker:** Glow, Border, Dim, Blur, Off. Blur uses public `NSVisualEffectView` only.
5. **Intensity** is a max-strength slider plus an automatic ramp that starts when `isSlouching` becomes true (after the existing grace period). Fade out when the user sits back inside the ellipse.
6. **Reduce Transparency** remaps Glow and Blur to Dim. **Reduce Motion** snaps intensity; no bloom or fade.
7. **Overlays never capture input.** `ignoresMouseEvents = true`. Esc is observed, not swallowed.
8. **Snooze** lives on the popover: 15 minutes, 45 minutes, until local tomorrow. Esc snoozes 15 minutes while a warning overlay is active.
9. **Focus:** if Focus is on *and* Focus Status is authorized, skip the notification banner. Overlay and sound still follow the user’s existing style/sound settings (no extra “during Focus” toggles).
10. **Tint:** Warm (amber, default), Cool (teal), Alert (red). Applies to every overlay style.
11. **Week** is ISO Monday 00:00 local through Sunday, not `Locale.current` `firstWeekday`.
12. **Episode** = one count on `isSlouching` false → true. Not each 45s nudge. Not in-grace leaning.
13. **Analytics count only while** tracking is on **and** headphones are connected **and** calibrated.
14. **No extra HUD/stats window.** Weekly strip and summary live in the existing popover.
15. **Desk vs Sofa** are two saved pitch+roll baselines, switched in the popover header.
16. **macOS 14+** remains the floor. `CMHeadphoneMotionManager` stays the motion source.

---

## Architecture

### Current objects (keep)

| Object | File | Role after this spec |
| --- | --- | --- |
| `AirPostureMacApp` + `AppDelegate` | `AirPostureMacApp.swift` | Accessory lifecycle, `MenuBarExtra`, owns tracker + settings + overlay manager + week store |
| `PostureTrackingManager` | `PostureTrackingManager.swift` | Motion, calibration, ellipse, grace, `isSlouching`, `postureBand`, `coachingCaption` |
| `AlertService` | `AlertService.swift` | Banner + sounds, 45s throttle, Focus banner skip, sit-up chime |
| `MenuBarView` | `MenuBarView.swift` | The one popover console |
| `PostureGaugeView` | `PostureGaugeView.swift` | Hero attitude instrument |
| `MenuBarIcon` | `MenuBarIcon.swift` | Status symbol; gains a family picker |

Do not add a second `WindowGroup`, `NSWindowController` HUD, or settings scene.

### New objects

| Object | Responsibility |
| --- | --- |
| `AirPostureSettings` | `ObservableObject` for UI prefs (style, strength, tint, sound, icon family, 2× grace, sit-up chime, volume). Persist in `UserDefaults`. |
| `WarningOverlayManager` | Owns one borderless `NSPanel` per screen. Drives visibility and strength from tracker + settings + snooze + accessibility. |
| `WeeklyAnalyticsStore` | 1 Hz sampling into daily JSON buckets under Application Support. Publishes this-week and last-week summaries for the popover. |

`PostureTrackingManager` stays the source of truth for pose. It gains Desk/Sofa baselines and a published `isSlouching` edge the store can observe. It does **not** draw overlays or write analytics files.

Suggested wiring in `AirPostureMacApp`:

```
AppDelegate.applicationDidFinishLaunching
  → accessory policy (already)
  → AlertService.requestNotificationAccess() (already)
  → AlertService.requestFocusStatusAccess() (new)

MenuBarExtra
  → MenuBarView(tracker, settings, weekStore, overlayManager)

WarningOverlayManager.init(tracker, settings)
WeeklyAnalyticsStore.init(tracker)
```

Overlay panels are not user windows: not in the Window menu, not Cmd-Tab, `nonactivatingPanel`, never call `makeKey()`.

### What stays local

No network, no accounts, no cloud analytics. Week JSON is the only new file. Settings stay in `UserDefaults` next to today’s keys (`isTrackingEnabled`, `sensitivityDegrees`, `gracePeriodSeconds`, `baselinePitchDegrees`, `baselineRollDegrees`).

---

## Overlay

### When it appears

Show the overlay when **all** of these are true:

- `settings.warningStyle != .off`
- snooze is inactive
- `tracker.isSlouching == true` (grace already elapsed)

Hide (fade, or snap if Reduce Motion) when any of those becomes false. Sitting up (`isSlouching` false → user back inside the ellipse) is the normal hide path.

The overlay does **not** appear during `.leaning` (in-grace). That interval is still icon-orange + gauge progress only.

If style is Off, snooze still suppresses sound and banner. Tracking and analytics keep running.

### Panel rules (every style)

One `NSPanel` per `NSScreen`, covering `screen.frame` (menu bar included so the vignette is even). Rebuild the set on `NSApplication.didChangeScreenParametersNotification`.

Required configuration:

- `styleMask`: `[.borderless, .nonactivatingPanel]`
- `isFloatingPanel = true`
- `level = .statusBar`
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`
- `ignoresMouseEvents = true`
- `hidesOnDeactivate = false`
- `isOpaque = false`
- `backgroundColor = .clear`
- `hasShadow = false`
- `animationBehavior = .none` (we animate opacity/strength ourselves)

Do **not** set `sharingType` tricks, `CGWindowListCreateImage`, or anything that triggers the Screen Recording TCC prompt. Do **not** use private CGS / `CGSSetWindowBackgroundBlurRadius` symbols.

Click-through is absolute. Overlays must never become key, never appear in the accessibility keyboard loop as a focus trap, and never add buttons on the panel itself. All controls stay in the popover.

### Styles

Strength below is `effectiveStrength`, 0...1, after ramp, slider, and accessibility remaps.

**Glow (default).** Soft vignette: a radial / edge gradient in the selected tint, opaque at the display edges, fully transparent in the center (~55% of the short axis). No center fill. At strength 1.0, edge alpha is 0.55. This is the “your screen is breathing at you” look.

**Border.** A rounded inset frame inset 10pt from `screen.frame`, stroke width `4 + 10 * strength` points, tint color at alpha `0.45 + 0.45 * strength`. Interior stays clear.

**Dim.** Full-frame fill, tint mixed 70% toward black, alpha `0.10 + 0.28 * strength`.

**Blur.** Public `NSVisualEffectView` only:

- `material = .fullScreenUI` (falls back to `.hudWindow` if needed)
- `blendingMode = .behindWindow`
- `state = .active`
- overlay a tinted color view at alpha `0.06 + 0.16 * strength`

`.behindWindow` is the supported window-server blur. It does not require Screen Recording.

**Off.** No panels on screen. Destroy or hide all panels.

### Intensity ramp and fade

Let `maxStrength` be the slider (0.20...1.00, default 0.70).

When `isSlouching` flips true:

- `t = seconds since that flip`
- `u = min(1, t / 8)` over **8 seconds**
- `ramp = u * u * (3 - 2 * u)` (smoothstep)
- `effectiveStrength = (0.20 + 0.80 * ramp) * maxStrength`

So the overlay is visible immediately at 20% of the user’s max, then blooms to full max over 8s.

When hiding because the user sat up: fade `effectiveStrength` to 0 over **350 ms**, then order the panels out.

**Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`):

- No bloom: `effectiveStrength = maxStrength` on the first frame of slouch.
- No fade: hide immediately.

**Reduce Transparency** (`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`):

- If the chosen style is Glow or Blur, render **Dim** instead, same tint and strength math.
- Border is unchanged (it is already a stroke).
- Off stays Off.

Observe both accessibility flags via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and restyle live.

### Tint

| Name | Role | Color (sRGB) |
| --- | --- | --- |
| Warm (default) | amber | `1.00, 0.62, 0.11` |
| Cool | teal | `0.18, 0.70, 0.68` |
| Alert | red | `0.91, 0.22, 0.21` |

Use these exact values for overlays so Glow/Border/Dim/Blur match. Menu-bar warning/slouch tints stay system orange / system red (see Icons); do not recolor the status item with Warm/Cool.

### Snooze

Snooze lives on `AirPostureSettings` as in-memory `@Published var snoozeEndsAt: Date?` (not written to `UserDefaults`). A relaunch is a fresh session. Overlay manager and `AlertService` both read this property; the popover and Esc write it.

| Control | Duration |
| --- | --- |
| Popover “15 min” | 15 minutes from tap |
| Popover “45 min” | 45 minutes from tap |
| Popover “Until tomorrow” | Until the next local midnight (`Calendar.current.startOfDay(for: now) + 1 day`) |
| Esc | 15 minutes, same as the first button |

While snoozed:

- Overlay hides immediately (snap if Reduce Motion, else 350 ms fade).
- `AlertService` must not play warning sounds or post banners.
- Analytics continue.
- Popover shows `Snoozed until {short time}` and a **Resume** button that clears snooze.

If the user is still slouching when snooze ends, the overlay comes back on the next manager tick (≤ 0.25s). Sound and banner still obey the 45s cooldown so ending a snooze cannot double-fire with a nudge that just happened.

**Esc behavior (locked):**

- Install `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` only while a warning overlay is actually on screen.
- If `event.keyCode == 53` (Escape), call snooze(15 min).
- Do **not** use a local monitor that swallows the event. Global monitors observe; Esc still reaches the frontmost app. This is how “never trap input” and “Esc snoozes” coexist for an accessory, click-through panel.
- If the popover is open and no overlay is showing, Esc does nothing extra (system popover dismiss is enough).
- If the popover is open *and* an overlay is showing, Esc snoozes 15 minutes; the popover may close as a side effect of losing key state — that is fine.

### Focus

Use the public Intents API only: `INFocusStatusCenter`. Do **not** listen for private DND distributed notifications (`_NSDoNotDisturbEnabledNotification` and friends).

Add to `Resources/Info.plist` and the Xcode target Info (required the moment Intents Focus APIs are linked — missing it can abort launch, same class of bug as a missing `NSMotionUsageDescription`):

```
NSFocusStatusUsageDescription
AirPosture hides sit-up banners while Focus is on. Overlays and sounds still follow your settings.
```

On launch, call `INFocusStatusCenter.default.requestAuthorization`. At each nudge, read `INFocusStatusCenter.default.focusStatus.isFocused` on the main actor. Treat Focus as on only when that optional is `true`.

Do **not** add `com.apple.developer.focus-status` to the ad-hoc signature. Same rule as `com.apple.developer.headphone-motion`: a restricted entitlement on an ad-hoc build can get AMFI to kill the app. Usage description + the TCC prompt is the local path. A Developer ID build may add the entitlement later; that is outside this slice.

| Focus Status auth | Focus on? | Banner | Overlay | Sound |
| --- | --- | --- | --- | --- |
| Denied / not determined | unknown | Post as today | Follow style | Follow sound settings |
| Authorized | false | Post as today | Follow style | Follow sound settings |
| Authorized | true | **Skip** | Follow style | Follow sound settings |

No additional Focus toggles. “User-optional” means the existing style picker (including Off) and sound controls.

### Relationship to today’s nudge

`PostureTrackingManager.evaluatePosture` already calls `AlertService.shared.nudgeIfAllowed()` when `isSlouching` is true. Keep a single call site there. At launch, give `AlertService` a reference to `AirPostureSettings`. Change the call to `nudgeIfAllowed(slouchElapsedSeconds:gracePeriodSeconds:)` so the 2×-grace gate can see the live timer. Gates, in order; return on the first failure:

1. `settings.snoozeEndsAt` is in the future → silence (no sound, no banner).
2. Optional 2× grace: `slouchElapsedSeconds < 2 * gracePeriodSeconds` → silence (overlay is already up from `isSlouching`).
3. Existing 45s cooldown since the last warning attempt → silence.
4. Play the selected pack at `settings.soundVolume`.
5. If `focusStatus.isFocused == true`, skip the banner; otherwise post today’s notification.

`WarningOverlayManager` observes `isSlouching` independently and never posts notifications.

---

## Analytics

### Eligibility

A second counts if and only if:

1. `isTrackingEnabled == true`
2. `connectionStatus == .connected`
3. `isCalibrated == true` (both pitch and roll baselines present for the **active** preset)

Paused, searching, disconnected, uncalibrated, or authorization-denied time is not monitored and does not increment off-neutral or episodes.

### Daily buckets

Store one row per local calendar date (`yyyy-MM-dd` in the user’s current timezone).

| Field | Meaning |
| --- | --- |
| `monitoredSeconds` | Eligible seconds |
| `offNeutralSeconds` | Eligible seconds where `isPastThreshold == true` (in-grace leaning **and** sustained slouch) |
| `slouchEpisodes` | Count of `isSlouching` rising edges |

### Episode rule

Subscribe to `tracker.$isSlouching` (or an equivalent `isSlouching` did-set) for edges. The 1 Hz timer only adds seconds; it must not be the sole episode detector (a short slouch could sit between ticks).

- If eligible AND `isSlouching` went `false → true`, add 1 episode.
- Do not increment on subsequent 45s nudges.
- Do not increment when `isPastThreshold` is true but `isSlouching` is still false.
- Sitting up then slouching again later in the day is a new episode.
- Disconnect / pause / lose calibration resets the previous flag to false without counting an episode.

### Sampling

`WeeklyAnalyticsStore` runs a 1 Hz `Timer` on the main actor. Each tick:

- If eligible, `monitoredSeconds += 1`.
- If eligible and `isPastThreshold`, `offNeutralSeconds += 1`.
- Apply the episode edge rule.
- Flush to disk at most every 10 seconds, and always on `NSApplication.willTerminateNotification`.

Do not write from the Core Motion queue. Do not keep a per-session event log.

### Week math

Use a dedicated `Calendar` configured as ISO-8601 Monday-start, **local timezone**:

```
var calendar = Calendar(identifier: .iso8601)
calendar.timeZone = .current
// ISO-8601 already: firstWeekday = Monday
```

- This week = `[startOfDay(Monday of this ISO week), startOfDay(next Monday))`.
- Last week = the seven local dates immediately before this week’s Monday.
- Do **not** read `Locale.current.calendar.firstWeekday`. Sunday-start locales still show Mon–Sun.

The week strip is always seven bars labeled **M T W T F S S** in that order. Highlight the bar whose local date is today.

### Metrics shown in the popover

From summed buckets of this week (and last week for the delta):

| Metric | Formula |
| --- | --- |
| % upright | If `monitoredSeconds == 0`: treat as no data. Else `round(100 * (1 - offNeutralSeconds / monitoredSeconds))` as an integer percent. |
| Slouch episodes | Sum of `slouchEpisodes`. |
| Minutes off-neutral | `round(offNeutralSeconds / 60)` as an integer minute count. |
| vs last week | Integer difference of this-week % upright minus last-week % upright, in points. |

Last-week comparison is omitted entirely when last week’s `monitoredSeconds == 0` (first week of use, or a week with no eligible time).

In-grace leaning counts against % upright because it increments `offNeutralSeconds`. That is intentional: the week view answers “how much of monitored time were you past the ellipse?”, not “how often did we beep?”.

### Retention

Keep daily buckets whose date is **≥ today − 90 local calendar days**. On every flush, drop older keys. Ninety days is enough for “vs last week” and a short look-back without a database.

### File

```
~/Library/Application Support/AirPosture/weekly-analytics.json
```

Create the `AirPosture` directory if needed. Write atomically: encode to a sibling `weekly-analytics.json.tmp`, then `replaceItem` / `replace`.

---

## Console / UI

The popover is the only console. Current width is 320pt; this slice uses **360pt**, padding 16.

Top-to-bottom layout:

1. **Header** — title + Desk/Sofa segmented control + connection badge.
2. **Hero gauge** — upgraded `PostureGaugeView`.
3. **Coach chip** — one line.
4. **Week strip** — 7 bars + summary line.
5. **Calibrate** — existing prominent button, still Command-K.
6. **Options** — `DisclosureGroup`, **collapsed by default**.
7. **Errors / Motion permission** — existing captions.
8. **Footer** — version + Quit.

Do not add a second page, tab bar, or “Open Stats” button.

### Header presets (Desk / Sofa)

Segmented control: **Desk** | **Sofa**. Default **Desk**.

Each preset stores its own `baselinePitchDegrees` + `baselineRollDegrees`.

- **Set Neutral Posture** writes the live pitch/roll into the *active* preset and applies it immediately (same as today’s `calibrate()`).
- Switching segment applies that preset’s baselines at once. If the target preset has never been calibrated, `isCalibrated` is false, the gauge goes idle, and analytics pause until the user calibrates on that preset.
- Migration: existing `baselinePitchDegrees` / `baselineRollDegrees` UserDefaults values become the Desk pair. Sofa starts empty.
- Desk **is** the existing `baselinePitchDegrees` / `baselineRollDegrees` keys. Do not introduce a parallel `deskBaseline*` pair. Sofa uses `sofaBaselinePitchDegrees` / `sofaBaselineRollDegrees`. Active preset key: `activePosturePreset` = `desk` | `sofa`.

Place the segmented control in the header, left of the connection badge. Keep the “AirPosture” title.

### Hero gauge

Upgrade `PostureGaugeView` / `AttitudePad` in place:

- Attitude pad height **188pt** (was 148).
- Threshold ellipse is a **solid 2pt ring** (not dashed): green when `.upright`, orange when `.leaning`, red when `.slouching`, secondary when idle bands.
- Marker is 14pt (was 12) with the existing white halo.
- **Motion trail:** keep the last **8** marker positions sampled at ~8 Hz. Draw them as circles 10→4pt, opacity 0.35→0.05, oldest first. Reduce Motion: current marker only, no trail.
- Keep the seated/stand figure overlay, slightly larger (30pt).

Idle / uncalibrated / disconnected still pins the marker at center and shows “—”.

### Coach chip

Replace the separate caption + two `AxisReadout` cards with **one** capsule row:

- Leading: `tracker.coachingCaption` (existing copy: “Upright”, “Lift your chin”, “Recenter”, etc.).
- Middle: dominant axis title (`Tilt` or `Lean`) at secondary weight, hidden when not calibrated.
- Trailing: signed values `Tilt {v}°` and `Lean {v}°` using one decimal, leading `+` when `> 0.05`, leading `−` (Unicode minus, U+2212) when `< −0.05`, no sign when essentially zero. Dim the non-dominant axis.

Keep one VoiceOver element for the gauge + chip group (`accessibilityElement(children: .combine)` on the gauge container). Hide the chip from VoiceOver so the caption is not spoken twice. The combined value stays: caption + both signed angles.

Grace progress bar stays under the chip, only for `.leaning` and `.slouching`.

### Week strip

Seven equal columns, Mon → Sun.

- Bar height maps 0...100% upright onto a 36pt track.
- Days with `monitoredSeconds == 0`: 2pt hairline at the baseline, accessibility value “No data”.
- Today: filled with system green at 0.85 opacity, plus a 1pt stroke.
- Other days with data: primary at 0.28 opacity.
- Single-letter labels under bars: M T W T F S S. Today’s label is `primary`; others `secondary`.

Summary line directly under the bars, caption font, secondary color, one line, wrapping allowed:

```
{pct}% upright · {n} slouch episode(s) · {m} min off-neutral · {±d} pts vs last week
```

Examples:

- `72% upright · 11 slouch episodes · 38 min off-neutral · +6 pts vs last week`
- `64% upright · 1 slouch episode · 12 min off-neutral` (no last-week data)
- `No monitored time this week` when this week’s `monitoredSeconds == 0`

Use `episode` vs `episodes` correctly. Signed delta uses `+` / `−` and the word `pts`.

### Options (collapsed)

`DisclosureGroup("Options")` contains, in this order:

1. Tracking toggle (existing)
2. Sensitivity slider 5...30° (existing)
3. Grace period slider 1...15s (existing)
4. Warning style picker (Glow / Border / Dim / Blur / Off)
5. Max strength slider 20...100%, label shows percent
6. Sound pack picker (Pop / Tink / Purr / Bottle / Morse)
7. Sound volume slider 10...80%
8. “Wait for 2× grace before sound” toggle, default off
9. Icon style picker (Posture figure / Horizon cross / Minimal dot)
10. Overlay tint picker (Warm / Cool / Alert)
11. Snooze row: 15 min, 45 min, Until tomorrow; or snooze status + Resume
12. Sit-up chime toggle, default off

Help copy (tooltips):

- Warning style: “Edge glow is default. Overlays never block clicks.”
- Max strength: “Ceiling for the overlay. It ramps up after the grace period.”
- 2× grace: “Keep the overlay, but delay sound and banner until you have been slouching for twice the grace period.”
- Sit-up chime: “One soft tick when you return upright. Off by default.”

---

## Customization

### Icons

User picks one **symbol family**. State colors stay as today.

| Family | Idle / uncalibrated / paused | Upright | Warning (`.leaning`) | Slouch (`.slouching`) |
| --- | --- | --- | --- | --- |
| **Posture figure** (default) | `airpodspro` (today) | `figure.stand`, template | `figure.seated.side`, system orange | `figure.seated.side`, system red |
| **Horizon cross** | `plus`, template | `plus`, template | `plus`, orange, rotated ±12° when lean-dominant | `plus`, red, same lean rotation |
| **Minimal dot** | `circle`, template | `circle.fill`, template | `circle.fill`, orange, shifted 2pt along the lean sign | `circle.fill`, red, same shift |

Disconnected is `airpodspro` in every family (same as today) so a missing headset does not look like a posture state.

Lean-dominant hint: only when `dominantAxis == .lean` and band is `.leaning` or `.slouching`. Rotate Horizon by `sign(rollDeltaDegrees) * 12` degrees. Shift Minimal dot by `sign(rollDeltaDegrees) * 2` points on X. Tilt-dominant uses the unrotated / unshifted variant.

Upright is always template-tinted (follows menu-bar appearance). Warning is orange. Slouch is red. Do not apply Warm/Cool overlay tints to the status item.

Accessibility labels on `MenuBarIcon` stay the existing band sentences.

### Sounds

Local system AIFF files via `AVAudioPlayer`, same fallback as today (`NSSound(named:)`).

| Pack | Path | Default? |
| --- | --- | --- |
| Pop | `/System/Library/Sounds/Pop.aiff` | yes |
| Tink | `/System/Library/Sounds/Tink.aiff` | |
| Purr | `/System/Library/Sounds/Purr.aiff` | |
| Bottle | `/System/Library/Sounds/Bottle.aiff` | |
| Morse | `/System/Library/Sounds/Morse.aiff` | |

Rules:

- Volume slider maps to `AVAudioPlayer.volume` in **0.10...0.80**. Default **0.45** (today’s hardcoded value).
- Throttle remains **45 seconds** from the last *warning* sound or banner attempt (`AlertService` cooldown). Sit-up chime does not start or reset that cooldown.
- Optional **“Wait for 2× grace before sound”**: first warning sound + banner wait until `slouchElapsedSeconds >= 2 * gracePeriodSeconds`. Overlay still starts at 1× grace (`isSlouching`). If the user sits up before 2×, no sound and no banner for that episode.
- Missing file: try `NSSound(named:)` with the same name; if that fails, skip audio for that fire (do not `NSSound.beep()`, it is too aggressive).

**Sit-up chime** (default **off**): on `isSlouching` true → false, if the toggle is on, snooze is inactive, and the user is still eligible (tracking on, connected, calibrated), play **Tink** at `0.40 * warningVolume`. If the warning pack is already Tink, play **Pop** at the same reduced volume so recovery is a different tick. Disconnect, pause, or lost calibration must not chime. Ignore Focus for the chime (no banner is involved).

---

## Data model

### UserDefaults keys

Existing keys remain valid.

| Key | Type | Default |
| --- | --- | --- |
| `isTrackingEnabled` | Bool | true |
| `sensitivityDegrees` | Double | 10 |
| `gracePeriodSeconds` | Double | 5 |
| `baselinePitchDegrees` | Double? | Desk pitch (legacy + Desk) |
| `baselineRollDegrees` | Double? | Desk roll (legacy + Desk) |
| `sofaBaselinePitchDegrees` | Double? | nil |
| `sofaBaselineRollDegrees` | Double? | nil |
| `activePosturePreset` | String `desk`\|`sofa` | `desk` |
| `warningStyle` | String | `glow` |
| `maxOverlayStrength` | Double | 0.70 |
| `overlayTint` | String | `warm` |
| `soundPack` | String | `pop` |
| `soundVolume` | Double | 0.45 |
| `soundAfterDoubleGrace` | Bool | false |
| `iconFamily` | String | `postureFigure` |
| `sitUpChimeEnabled` | Bool | false |

In-memory only (not a UserDefaults key): `snoozeEndsAt: Date?` on `AirPostureSettings`. Computed `isSnoozed` is `snoozeEndsAt.map { $0 > Date() } ?? false`.

String raw values:

- `warningStyle`: `glow` | `border` | `dim` | `blur` | `off`
- `overlayTint`: `warm` | `cool` | `alert`
- `soundPack`: `pop` | `tink` | `purr` | `bottle` | `morse`
- `iconFamily`: `postureFigure` | `horizonCross` | `minimalDot`

Clamp on read: strength 0.20...1.00, volume 0.10...0.80, existing sensitivity/grace clamps unchanged.

### Analytics JSON

```json
{
  "schemaVersion": 1,
  "days": {
    "2026-09-01": {
      "monitoredSeconds": 18320,
      "offNeutralSeconds": 2410,
      "slouchEpisodes": 7
    }
  }
}
```

Unknown future `schemaVersion`: read what we can; never delete the file because of a newer version. Writer always writes `schemaVersion: 1` until a later spec says otherwise.

Corrupt JSON: rename the file to `weekly-analytics.corrupt-{timestamp}.json` and start a fresh `schemaVersion: 1` document. Do not crash launch.

### In-memory types (implementer names may vary)

```
enum WarningStyle: String { case glow, border, dim, blur, off }
enum OverlayTint: String { case warm, cool, alert }
enum SoundPack: String { case pop, tink, purr, bottle, morse }
enum IconFamily: String { case postureFigure, horizonCross, minimalDot }
enum PosturePreset: String { case desk, sofa }

struct DayBucket: Codable {
  var monitoredSeconds: Int
  var offNeutralSeconds: Int
  var slouchEpisodes: Int
}

struct WeekSummary {
  var percentUpright: Int?          // nil if no monitored time
  var slouchEpisodes: Int
  var offNeutralMinutes: Int
  var vsLastWeekPoints: Int?        // nil if last week unmonitored
  var dailyUprightPercents: [Int?]  // index 0 = Monday, 7 values
}
```

`isSlouching` and `isPastThreshold` remain on `PostureTrackingManager` as they are today.

---

## Accessibility

- Overlays are decorative. Each panel’s `accessibilityElement` is false / ignored. VoiceOver stays on the user’s real UI. State is spoken via the existing menu-bar label and the popover gauge.
- Reduce Transparency → Dim for Glow/Blur (see Overlay).
- Reduce Motion → snap show/hide, no trail, no bloom.
- Increase Contrast: Border stroke alpha minimum 0.75 when that setting is on; Glow/Dim edge/fill alpha multiplied by 1.15, clamped to 1.0. Read `accessibilityDisplayShouldIncreaseContrast`.
- Every Options control has a label, value, and hint (see Options help copy). Snooze buttons need labels “Snooze 15 minutes”, “Snooze 45 minutes”, “Snooze until tomorrow”.
- Week bars: container label “This week, Monday through Sunday”. Each bar value is “{weekday}, {pct} percent upright” or “{weekday}, no data”.
- Keyboard: Tracking, sliders, and snooze stay in the popover tab loop. Overlay panels are not in that loop. Command-K calibrate and Command-Q quit stay.
- Dynamic Type: popover uses system fonts (headline / subheadline / caption) so it respects larger sizes; week bars stay 36pt track so the window does not explode. Allow the popover height to grow; keep width 360.

---

## Error handling

| Situation | Behavior |
| --- | --- |
| Motion authorization denied | Existing orange caption. No overlay. No analytics. |
| Headphones disconnected / searching | Existing badge. Hide overlay. Reset slouch state (already). Stop incrementing analytics. |
| Tracking paused | Existing band `.paused`. Hide overlay. Stop analytics. |
| Active preset uncalibrated | Gauge idle, calibrate enabled if connected. No overlay. No analytics. |
| Sound file missing | `NSSound(named:)` fallback; then silence. Still post banner if Focus allows. |
| Blur material unavailable | Draw Dim with the same tint/strength. |
| Screen parameters change | Tear down panels, recreate for the new `NSScreen.screens`. |
| Analytics write fails | Keep in-memory buckets; retry next 10s flush. Set a published `lastStoreError` only if three consecutive writes fail; show a caption in the popover, not a modal. |
| Corrupt analytics file | Quarantine and start fresh (see Data model). |
| Focus Status denied | Treat Focus as off; banners work as today. |
| UserDefaults missing / garbage | Clamp / default table above. Never crash `init`. |
| Overlay panel fails to create | Skip that screen; still try others. Do not fall back to a key window. |

`lastErrorMessage` from Core Motion stays as today (red caption). Do not reuse it for analytics I/O.

---

## Testing

No new XCTest target is required to *start* implementation, but the store and overlay gates must be unit-testable without AirPods. Extract ISO week bounds, bucket increment, and episode-edge logic as pure functions (or a testable store with a fake clock).

### Overlay

1. Style Glow, slouch past grace → one panel per display, `ignoresMouseEvents == true`, clicks reach the app below.
2. Move mouse through the vignette; menu bar and a Safari window still receive clicks.
3. Switch style to Border / Dim / Blur / Off while slouching; restyle without creating a second panel per screen.
4. Unplug an external display; panel count matches `NSScreen.screens`.
5. Sit up → fade 350 ms (or immediate with Reduce Motion).
6. Reduce Transparency on + style Blur or Glow → visual Dim, not blur/vignette.
7. Reduce Motion on → no trail, snap to `maxStrength`, snap hide.
8. Strength slider 20% vs 100%: peak alpha changes; ramp still 8s unless Reduce Motion.
9. Snooze 15 / 45 / tomorrow hides overlay and blocks sound/banner; Resume brings overlay back if still slouching.
10. Esc while overlay visible starts a 15 min snooze and does not prevent Esc in the frontmost app (type in Notes, press Esc, Notes still handles it).
11. Style Off: no panels; snooze still mutes sound/banner.

### Focus and alerts

12. Focus authorized + Focus on → no banner; overlay and sound still fire.
13. Focus authorized + Focus off → banner + sound as today.
14. Focus denied → banner as today.
15. 2× grace on, grace 5s: overlay at 5s, first sound/banner at 10s.
16. 2× grace on, sit up at 8s: no sound, no banner.
17. Nudge throttle: two `isSlouching` holds 20s apart → one sound; 50s apart → two sounds. Episode count is still 2 if they sat up between.
18. Sit-up chime off (default): silence on recover. On: one softer Tink (or Pop if pack is Tink). Warning cooldown unchanged.

### Analytics

19. Eligible 60s upright → `monitoredSeconds` 60, `offNeutralSeconds` 0, episodes 0, % upright 100.
20. Eligible 50s upright + 10s in-grace (not slouching) → off-neutral 10, episodes 0, % upright 83.
21. Cross grace once, stay slouching 90s (two nudges) → episodes 1.
22. Slouch, sit up, slouch again → episodes 2.
23. Pause tracking for 30s in the middle → those seconds are absent from both counters.
24. Disconnect during slouch → no extra episode; slouch flag clears.
25. Week starting Sunday in US locale: strip still Mon–Sun; “today” highlight is the correct local date.
26. A date 91 days ago disappears after the next flush.
27. Corrupt JSON on launch → app runs; new file created; old file quarantined.
28. First week of use: summary has no “vs last week” clause.

### Console

29. Launch: Options collapsed; Desk selected; gauge is the tall hero; week strip visible.
30. Sofa with no baseline: uncalibrated empty gauge; calibrate writes Sofa only; switching back to Desk restores Desk baselines.
31. Icon family cycling updates the status item without changing band colors.
32. Coach chip shows signed Tilt/Lean and existing captions (“Lift your chin” / “Recenter”).
33. VoiceOver on the status item still announces band; overlay is not in the VO hierarchy.

### Regression

34. `NSMotionUsageDescription` still present; missing it must not be “fixed” by this slice.
35. Do not add `com.apple.developer.headphone-motion` or `com.apple.developer.focus-status` to the ad-hoc signature.
36. `LSUIElement` stays true; app remains accessory.
37. Raw `.build/release/AirPosture` still must not be the launched form (existing packaging).

---

## Out of scope

Explicitly **do not** build:

- Always-on HUD or detached stats window
- Spoken / VoiceOver-polite cue audio beyond the sit-up tick
- Private CGS blur, undocumented window-server calls
- Streak heatmaps, GitHub-style calendars
- Tilt-vs-lean pie or axis breakdown charts
- Session database, CSV export, iCloud sync
- Blocking overlays, click-to-dismiss overlays, or full-screen lock
- Screen Recording entitlement or screen-capture APIs
- Locale week-start picker (ISO Monday is fixed)
- Extra Focus-specific overlay/sound toggles
- Windows / iOS / menu-bar-extra `.menu` style
- Changing the ellipse math, lean-to-tilt ratio (0.5), smoothing (α = 0.4), or grace range (1...15s)
- Networked analytics or accounts

---

## MVP slice

Ship the whole spec as **one** vertical slice, in this order so each step is demoable:

1. **`AirPostureSettings` + Options disclosure** — persist style/strength/tint/sound/icon/chime/2× grace. No overlay yet; Pop still plays.
2. **Desk / Sofa baselines** — header switch + calibrate writes the active pair; migrate today’s keys to Desk.
3. **`WarningOverlayManager`** — Glow per display, click-through, ramp/fade, snooze + Esc, Reduce Transparency / Reduce Motion.
4. **Remaining styles** — Border, Dim, Blur (`NSVisualEffectView`), Off; tint applied to all.
5. **`AlertService` upgrade** — pack, volume, Focus banner skip, 2× grace, sit-up chime. Keep 45s throttle.
6. **`WeeklyAnalyticsStore`** — 1 Hz eligible sampling, ISO week, 90-day prune, atomic JSON.
7. **Popover hero + coach chip + week strip** — upgrade `PostureGaugeView`, 360pt console, summary line.
8. **Icon families** — Posture figure / Horizon cross / Minimal dot with lean hint.

Done when: a calibrated, connected user who slouches past grace sees a click-through Glow on every display, hears Pop (unless they changed the pack), still gets the banner unless Focus is on, can snooze from the popover or Esc, and can open the menu-bar console to see this week’s Mon–Sun upright bars without any other window.

---

## Existing behavior the implementer must not regress

From the current sources, treat these as invariants:

- Pitch = tilt (negative = chin down). Roll = lean. Combined ellipse: `hypot(tiltNorm, leanNorm) >= 1`.
- Lean threshold = `max(4, sensitivity * 0.5)`.
- `coachingCaption`: uncalibrated / waiting / paused / “Upright” / “Tilting forward” / “Leaning aside” / “Lift your chin” / “Recenter”.
- `PostureBand`: `uncalibrated`, `waitingForHeadphones`, `upright`, `leaning`, `slouching`, `paused`.
- Banner copy: title “Sit up straight!”, body “Your head has drifted past your tilt or lean threshold.”, `content.sound = nil` (audio is AVFoundation, not the notification sound).
- Notification id: `airposture.slouch`.
- Motion queue name: `com.macposture.airposture.motion`.
- Health check: 5s silence → searching, 10s → disconnected.

---

## Locked interpretations

| Topic | Interpretation locked |
| --- | --- |
| “User-optional” overlay/sound under Focus | Existing style + sound settings. No extra Focus toggles. Only the banner auto-skips. |
| Off-neutral minutes | `isPastThreshold` time, including in-grace. Episodes stay slouch-edge only. |
| % upright | `1 - offNeutral/monitored` of eligible time. |
| Esc vs click-through | Global key monitor, observe-only, only while overlay is on screen. |
| Snooze persistence | In-memory; cleared on quit. |
| 2× grace | Delays sound + banner only; overlay still at 1× grace. |
| Sit-up tick | Tink at 40% of warning volume; Pop if pack is already Tink. |
| Blur | Public `NSVisualEffectView` + `.behindWindow`. No Screen Recording. |
| Reduce Transparency | Glow **and** Blur become Dim. Border unchanged. |
| Week start | ISO Monday local, even in Sunday-first locales. |
| Trailing 90 days | Local calendar dates, prune on flush. |
| Overlay vs extra window | Per-screen nonactivating panels are not user windows. |
| Desk/Sofa + analytics | Eligibility uses the *active* preset’s calibration. |
| Icon tint vs overlay tint | Overlay Warm/Cool/Alert never recolors the menu-bar item. |
| Focus detection | Public `INFocusStatusCenter.focusStatus.isFocused` at nudge time. No private DND notifications. No `com.apple.developer.focus-status` on ad-hoc. |
| Desk baselines | Existing `baselinePitchDegrees` / `baselineRollDegrees` keys. Sofa is the only new pair. |
| Sit-up chime trigger | Eligible sit-up only. Not disconnect, pause, or lost calibration. |
