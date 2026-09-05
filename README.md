# AirPosture

A macOS menu-bar posture coach. It reads the motion sensors in spatial-audio AirPods and nudges you when your head stays tilted or leaned off your chosen baseline.

Compatible with **AirPods Pro**, **AirPods Max**, **AirPods 3 / 4**, and other Apple headphones that support spatial audio with dynamic head tracking. Original AirPods and AirPods 2 have no IMU and will stay **Disconnected**.

## Requirements

- **macOS 14.0+** — Apple added `CMHeadphoneMotionManager` to the Mac in macOS 14 (Sonoma). It is not available on macOS 13.
- AirPods (or Beats) with head tracking, in your ears
- Motion & Fitness permission
- Notification permission (for the “Sit up straight!” banner)
- Optional: Focus Status permission (hides the banner while Focus is on)

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
6. Leave tracking on. After you stay past the sensitivity ellipse for the grace period (default 5 seconds), AirPosture:
   - tints every display with a click-through **Glow** overlay (it ramps up over a few seconds)
   - plays **Pop**
   - posts a “Sit up straight!” banner (skipped while Focus is on *and* Focus Status is allowed)

Alerts are throttled to once every 45 seconds. Overlays never block clicks. Press **Esc** while a warning overlay is visible to snooze 15 minutes (macOS may ask for Input Monitoring so Esc still reaches the app you are typing in).

## Using the console

The popover is the only window.

- **Attitude pad** — live tilt and lean, with a short motion trail.
- **Coach chip** — a one-line cue plus signed Tilt / Lean values.
- **This week** — a compact upright/slouch/off-neutral summary stays visible; expand the full-width row for Monday–Sunday bars and hover a day for its exact value. A week starts Monday in your local timezone. Only time while tracking is on, AirPods are connected, and the active preset is calibrated counts.
- **Desk / Sofa** — two saved neutrals. Switching applies that preset immediately. An uncalibrated preset pauses the gauge and weekly stats until you calibrate it.
- **Options** (collapsed by default) — click anywhere on the row to open grouped Monitoring, Reminders, Appearance, and Pause & feedback controls. These include tracking, sensitivity, grace, head-turn behavior, overlay style and strength, sound, icon style, tint, snooze, and the optional sit-up chime.

Snooze hides the overlay and mutes sound and banners. Tracking and the week counters keep running. **Resume** clears snooze. Snooze is in-memory only; quitting AirPosture ends it.

## Customization

| Control | Default | Notes |
| --- | --- | --- |
| Warning style | Glow | Also Border, Dim, Blur (public system blur only), or Off. Reduce Transparency turns Glow/Blur into Dim. |
| Overlay tint | Warm | Warm / Cool / Alert. Colors the overlay, not the menu-bar icon. |
| Sound pack | Pop | Pop, Tink, Purr, Bottle, Morse. Volume 10–80%. |
| Icon style | Posture figure | Also Horizon cross and Minimal dot. Orange while you are off-neutral through grace; red once a slouch is sustained. |
| Ignore slouch when I turn | On | Pauses tilt/lean scoring past the turn-away angle. Yaw is session-relative only. |
| Turn-away angle | 35° | 20–60°. Only used when the look-away gate is on. |
| Show head turn | On | Rotates the bust left/right. Does not change scoring. |
| Sit-up chime | Off | A softer tick when you return upright. |

## How detection works

1. `CMHeadphoneMotionManager` streams `CMDeviceMotion` from the AirPods IMU.
2. **Pitch (tilt)**, **roll (lean)**, and **yaw (turn)** are validated, converted to degrees, and low-pass filtered (α = 0.4).
3. **Set Neutral Posture** stores pitch and roll for the active Desk or Sofa preset, and zeros **this session’s** heading (yaw is not persisted across launches or reconnects).
4. Live deltas: tilt = pitch − baseline (negative = chin down); lean = roll − baseline (either side); turn = wrap-aware yaw − session zero.
5. Off-neutral is scored as an **ellipse**: 10° of forward tilt *or* ~5° of side lean (lean is twice as sensitive). Combined motion can also cross the line even if neither axis does alone. **Yaw is not in the ellipse.**
6. With **Ignore slouch when I turn** on (default), if `|turn|` reaches the turn-away angle (default 35°), tilt/lean scoring pauses — overlay, banner, grace, and off-neutral week time stay quiet while you look aside. Monitored time still counts.
7. If a combined deviation holds for the grace period (and you are not gated as looking aside), the overlay appears and the sound/banner can fire. Returning inside the ellipse fades the overlay away.
8. The coach chip highlights the **dominant axis**, with copy like “Lift your chin” / “Recenter”, or **Looking aside** while the turn gate is active. **Show head turn** rotates the bust on Y without changing scoring.

## Project layout

```
Sources/AirPostureMac/
  AirPostureMacApp.swift          App lifecycle + MenuBarExtra
  PostureTrackingManager.swift    Core Motion, Desk/Sofa calibration, slouch timer
  AirPostureSettings.swift        Overlay, sound, icon, and snooze preferences
  WarningOverlayManager.swift     Per-display click-through warning panels
  WeeklyAnalyticsStore.swift      Local Monday–Sunday week counters
  AlertService.swift              Banner + system sounds via AVFoundation
  MenuBarView.swift               Menu-bar console
  PostureGaugeView.swift          Attitude pad, trail, coach chip, and bust
  InstrumentBustView.swift        SceneKit glass/metal bust
  MenuBarIcon.swift               Status symbol families
Resources/Info.plist              Motion, Focus Status, and LSUIElement keys
Sources/AirPostureCore/
  PostureGaugeMapping.swift       Pure pose mapping + yaw wrap/gate helpers
```

Privacy: all processing is local. No network calls, no accounts. Weekly totals live in `~/Library/Application Support/AirPosture/weekly-analytics.json` on this Mac and are pruned after 90 days.
