# AirPosture

A macOS menu-bar posture coach. It reads the motion sensors in spatial-audio AirPods and nudges you when your head stays tilted or leaned off your chosen baseline.

Compatible with **AirPods Pro**, **AirPods Max**, **AirPods 3 / 4**, and other Apple headphones that support spatial audio with dynamic head tracking. Original AirPods and AirPods 2 have no IMU and will stay **Disconnected**.

## Requirements

- **macOS 14.0+** — Apple added `CMHeadphoneMotionManager` to the Mac in macOS 14 (Sonoma). It is not available on macOS 13.
- AirPods (or Beats) with head tracking, in your ears
- Motion & Fitness permission
- Notification permission (for the “Sit up straight!” banner)
- Optional: Focus Status permission (hides the banner while Focus is on)
- **Swift 6.1+** to build from source. The bundled ColorSelector package requires Swift 6.1.

## Info.plist keys

These keys are already in `Resources/Info.plist`. If you recreate the target in Xcode, add them again — **missing `NSMotionUsageDescription` crashes the app** the moment motion updates start. Missing `NSFocusStatusUsageDescription` can abort launch once Focus Status APIs are linked.

```xml
<key>NSMotionUsageDescription</key>
<string>AirPosture uses the motion sensors in your AirPods to track head tilt and remind you to sit upright. Motion data never leaves this Mac.</string>

<key>NSFocusStatusUsageDescription</key>
<string>AirPosture hides sit-up banners while Focus is on. Overlays and sounds still follow your settings.</string>

<key>LSUIElement</key>
<true/>
```

| Key | Why it is required |
| --- | --- |
| `NSMotionUsageDescription` | Required by Core Motion on macOS. Without it, `startDeviceMotionUpdates` aborts the process. This string appears in the Motion & Fitness permission prompt. |
| `NSFocusStatusUsageDescription` | Required when using the public Focus Status API (`INFocusStatusCenter`). This string appears if macOS asks for Focus Status. |
| `LSUIElement` | Hides the Dock icon and Cmd-Tab entry so the app lives only in the menu bar. |

You do **not** need a Bluetooth usage string. Head pose comes from Core Motion, not a raw Bluetooth API.

If you use Xcode’s generated Info.plist instead of this file, set the same values in the target’s Info tab, or as build settings:

```
INFOPLIST_KEY_NSMotionUsageDescription = AirPosture uses the motion sensors in your AirPods…
INFOPLIST_KEY_NSFocusStatusUsageDescription = AirPosture hides sit-up banners while Focus is on…
INFOPLIST_KEY_LSUIElement = YES
```

Do **not** add `com.apple.developer.headphone-motion` or `com.apple.developer.focus-status` to an ad-hoc signature. Those restricted entitlements can make AMFI kill the app on launch. The usage strings plus the TCC prompts are enough for local use.

## Build & run

This Mac only has Command Line Tools in some setups. Either path works.

### Swift Package (no Xcode.app required)

```bash
chmod +x build.sh
make run
```

That compiles a release binary, wraps it in `AirPosture.app` (with the Info.plist above), ad-hoc signs it, and opens it.

Install into `/Applications`:

```bash
make install
```

Always launch the **`.app`**, never the raw `.build/release/AirPosture` binary. The bare executable has no Info.plist, so macOS kills it when it touches motion data.

Run the deterministic core and native integration checks with:

```bash
make test
```

The native sound-output probe is deliberately separate because it plays all five sounds:

```bash
make sound-probe
```

The checked-in `Vendor/ColorSelector` source is upstream v2.3.1 at commit `d73937d4c68894170001f331ce991ccaeffa73b5`. Its only compatibility change wraps preview-only macro blocks so Command Line Tools without `PreviewsMacros` can compile the package; runtime picker code is unchanged. Provenance and hashes are recorded in `Vendor/ColorSelector/UPSTREAM.json`.

### Xcode

1. Open `AirPostureMac.xcodeproj`
2. Select the **AirPosture** target
3. Choose your Team if you want a development signature (ad-hoc `-` also works locally)
4. Confirm Info contains `NSMotionUsageDescription`, `NSFocusStatusUsageDescription`, and `LSUIElement = YES`
5. Run (⌘R)

## First-run setup

1. Put on compatible AirPods and connect them to this Mac.
2. Launch **AirPosture**. A posture icon appears in the menu bar.
3. Allow **Motion & Fitness** when macOS asks. If you dismissed it: System Settings → Privacy & Security → Motion & Fitness.
4. Allow notifications if you want the sit-up banner.
5. Click the menu-bar icon. Sit the way you want to hold yourself, then **Set Neutral Posture** (⌘K). Desk is the default preset; switch to **Sofa** and calibrate again if you want a second baseline.
6. Leave tracking on. With the default early cue, a faint click-through **Glow** starts at 70% of the sensitivity ellipse and fades in over 3 seconds. If you remain past the real boundary for the grace period (default 5 seconds), AirPosture:
   - raises the overlay to its selected maximum
   - plays **Pop**
   - posts a “Sit up straight!” banner (skipped while Focus is on *and* Focus Status is allowed)

The early cue is visual only. It does not start grace, mark a slouch, create an episode, change the menu icon, or play/post an alert. Sound and banners still wait for the real boundary plus one grace period, or two grace periods when delayed sound is enabled. Alerts are throttled to once every 45 seconds. Overlays never block clicks. Press **Esc** while a warning overlay is visible to snooze 15 minutes (macOS may ask for Input Monitoring so Esc still reaches the app you are typing in).

## Using the console

The popover is the only window.

- **Expressive posture avatar** — a lightweight Coolio torso with complete arms and hands mirrors tilt, lean, and optional head turn with smooth, amplified movement. Black eyes and brows blink and shift from a relaxed smile to quiet concern with the current posture status. Brief eyebrow raises and small arm gestures respond to posture changes. Chest and shoulder movement illustrate the headphone attitude; they are not separate body measurements. Subtle breathing preserves the tracked pose.
- **Coach chip** — a one-line cue plus signed Tilt / Lean values.
- **This week** — a compact upright/slouch/off-neutral summary stays visible. Expand it for Monday–Sunday stacked bars: green is within sensitivity (including early-cue and look-away-gated time), orange is the grace countdown, red is sustained slouch, and gray is older off-neutral time that predates category splitting. Empty and future dates stay empty. Hover, click, or use the keyboard to select a day and inspect exact durations, percentages, and episodes. Time is monitored only while tracking is enabled, headphones are connected, and the active preset is calibrated.
- **History** — the expanded area also shows 7, 30, or 90 inclusive local-calendar days, ending today (30 days by default). Daily upright percentages use a fixed 0–100% scale. The dashed trailing trend weights each day by monitored duration over the seven calendar days ending there; its detail shows observed-day and monitored-time coverage. Missing dates break both lines, so gaps never imply continuous measurement. The comparison uses the latest seven days versus the preceding seven only when both contain monitored time.
- **Desk / Sofa** — two saved neutrals. Switching applies that preset immediately. An uncalibrated preset pauses the gauge and weekly stats until you calibrate it.
- **Options** (collapsed by default) — click anywhere on the row to open grouped Monitoring, Reminders, Appearance, and Pause & feedback controls. These include tracking, sensitivity, grace, head-turn behavior, overlay style and strength, sound, icon style, tint, snooze, and the optional sit-up chime.

Snooze hides the overlay and mutes sound and banners. Tracking and the week counters keep running. **Resume** clears snooze. Snooze is in-memory only; quitting AirPosture ends it.

## Customization

| Control | Default | Notes |
| --- | --- | --- |
| Warning style | Glow | Also Border, Dim, Blur (public system blur only), or Off. Reduce Transparency turns Glow/Blur into Dim. |
| Early visual cue | On | Start point 10–100% of the existing sensitivity ellipse in 5% steps; default 70%. Turning it off keeps the overlay hidden until grace expires and does not change scoring. |
| Fade-in | 3 seconds | 0.5–10 seconds in 0.5-second steps. Applies to the selected overlay response. |
| Max strength | 70% (Glow/Border/Dim), 5% (Blur) | 5–100% in 5% steps. Stored separately for every visible style; Reset restores that style's default and Warm color. |
| Overlay color | Warm | Warm / Cool / Alert presets plus a custom picker rendered by ColorSelector. Custom colors are stored as validated opaque sRGB; strength controls opacity separately. Each visible style remembers its own color. |
| Sound pack | Pop | Pop, Tink, Purr, Bottle, Morse. Volume 10–80%. Preview uses the selected pack and volume even while paused or snoozed, without changing analytics, banners, or warning cooldown. |
| Icon style | Posture figure | Also Horizon cross and Minimal dot. Orange while you are off-neutral through grace; red once a slouch is sustained. |
| Ignore slouch when I turn | On | Pauses tilt/lean scoring past the turn-away angle. Yaw is session-relative only. |
| Turn-away angle | 35° | 20–60°. Only used when the look-away gate is on. |
| Show head turn | On | Rotates the bust left/right. Does not change scoring. |
| Sit-up chime | Off | A softer tick when you return upright. |

Existing appearance preferences migrate once: the prior global strength initializes Glow, Border, and Dim (or 70% when absent), while Blur starts at 5%; the prior Warm/Cool/Alert tint initializes each visible style. Once a style has its own values, later launches do not overwrite them.

## How detection works

1. `CMHeadphoneMotionManager` streams `CMDeviceMotion` from the AirPods IMU.
2. **Pitch (tilt)**, **roll (lean)**, and **yaw (turn)** are validated, converted to degrees, and low-pass filtered (α = 0.4).
3. **Set Neutral Posture** stores pitch and roll for the active Desk or Sofa preset, and zeros **this session’s** heading (yaw is not persisted across launches or reconnects).
4. Live deltas: tilt = pitch − baseline (negative = chin down); lean = roll − baseline (either side); turn = wrap-aware yaw − session zero.
5. Off-neutral is scored as an **ellipse**: 10° of forward tilt *or* ~5° of side lean (lean is twice as sensitive). Combined motion can also cross the line even if neither axis does alone. **Yaw is not in the ellipse.**
6. With **Ignore slouch when I turn** on (default), if `|turn|` reaches the turn-away angle (default 35°), tilt/lean scoring pauses — overlay, banner, grace, and off-neutral week time stay quiet while you look aside. Monitored time still counts.
7. With the early cue on, the overlay starts at the configured fraction of the same ellipse and reaches 25% of its chosen maximum at the real boundary. Through grace it rises toward the maximum; the sound, banner, red menu state, and episode still begin only after grace. With the cue off, the overlay also waits until after grace. Returning toward neutral fades it away.
8. The coach chip highlights the **dominant axis**, with copy like “Lift your chin” / “Recenter”, or **Looking aside** while the turn gate is active. **Show head turn** rotates the bust on Y without changing scoring.

## Project layout

```
Sources/AirPostureMac/
  AirPostureMacApp.swift          App lifecycle + MenuBarExtra
  PostureTrackingManager.swift    Core Motion, Desk/Sofa calibration, slouch timer
  AirPostureSettings.swift        Overlay, sound, icon, and snooze preferences
  WarningOverlayManager.swift     Per-display click-through warning panels
  WeeklyAnalyticsStore.swift      Local Monday–Sunday week counters
  PostureAnalyticsView.swift      Weekly stacks, history chart, and details
  ReminderOptionsView.swift       Early cue, appearance, and sound controls
  SoundPlayback.swift             Selected-sound playback and fallback lifecycle
  AlertService.swift              Preview/warning policy and banners
  MenuBarView.swift               Menu-bar console
  PostureGaugeView.swift          Full-size bust stage, coach chip, and grace bar
  InstrumentBustView.swift        SceneKit frame loop and tracking input bridge
  BustSceneRig.swift              Cached rig controls, materials, and lighting
  BustDebugView.swift             Opt-in Debug-only animation tuning
  Resources/AirPostureBust.usdz   Optimized Coolio torso and posture/facial rig
  MenuBarIcon.swift               Status symbol families
Resources/Info.plist              Motion, Focus Status, and LSUIElement keys
Sources/AirPostureCore/
  PostureGaugeMapping.swift       Pure pose mapping + yaw wrap/gate helpers
  WarningIntensity.swift          Pure cue target and time-based envelope
  PostureAnalytics.swift          Versioned days, ranges, trends, and accumulation
DesignAssets/
  CoolioBust.blend                Editable Coolio derivative with named controls
  CoolioBust-preview.png          Source-rendered material preview
Tools/Blender/
  build_coolio_bust.py             Rebuilds the Coolio derivative, preview, and USDZ
```

Privacy: all processing is local. No network calls, no accounts. Analytics live in `~/Library/Application Support/AirPosture/weekly-analytics.json`. The app keeps exactly today plus the preceding 89 local-calendar dates. Version 1 totals migrate without loss to version 2; older off-neutral duration remains labeled “Earlier off-neutral, unsplit” because countdown and sustained portions cannot be reconstructed. New records preserve fractional monitored, off-neutral, countdown, and sustained durations plus episode counts. Invalid or unsupported future documents are rejected instead of silently overwritten.

Sound playback tries the selected system AIFF first, then the same named `NSSound` fallback; it never substitutes Pop for a failed selection. The player remains alive through completion, a second preview stops the first, and preparation/start/decode failures appear inline beside the reminder controls until a later playback succeeds.
