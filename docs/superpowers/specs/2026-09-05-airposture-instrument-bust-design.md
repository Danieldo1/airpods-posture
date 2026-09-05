# AirPosture instrument bust

Design spec for replacing the hero-gauge stickman with a centered glass/metal bust and a soft horizon wash. Implementation must follow this document.

**Status:** approved  
**Date:** 2026-09-05  
**Platform:** macOS 14+, SwiftUI `MenuBarExtra` with `.window` style, accessory app  
**Bundle ID:** `com.macposture.airposture`

This spec **supersedes** only one line in `2026-09-05-airposture-console-overlays-analytics-design.md`:

> Keep the seated/stand figure overlay, slightly larger (30pt).

Every other decision in that document stays in force: pad height 188pt, solid 2pt threshold ellipse, 14pt haloed pip, 8-sample trail at ~8 Hz, coach chip, grace bar, VoiceOver combine, overlays, week store, ellipse math, menu-bar icon families.

---

## Problem

The console already reads as an instrument: ellipse, crosshair, pip, trail. The SF Symbol on top (`figure.stand` / `figure.seated.side`) does not. It is both a traveling token and a person, and it makes the pad look like a toy.

Users want a presence that feels like an Apple object, not a cartoon, while keeping the bound as the “am I inside?” read.

Constraints that stay non-negotiable:

- Menu-bar popover only. No extra window, no Dock HUD.
- Public AppKit / SwiftUI / SceneKit only. No AvatarKit, no Memoji, no private frameworks.
- Motion data never leaves the Mac. No downloaded 3D assets.
- AirPods give pitch and roll. Optional session-relative yaw may rotate the bust and gate scoring when looking aside; it still does not join the tilt/lean ellipse. No face mesh or blend shapes.
- Reduce Motion must snap; it must not keep a looping idle.

---

## Decisions

These are locked. If a later idea conflicts with this list, this list wins.

1. **Centered bust, traveling pip.** The sculpture stays in the middle and only rotates. Distance-to-edge stays on the pip + trail.
2. **Instrument sculpture, not a face.** Smoked-glass ellipsoid head, short satin-metal neck, a hint of shoulders. No eyes, mouth, hair, skin-tone picker, or photo mapping.
3. **Horizon wash is atmosphere, not a flight deck.** Soft cool-above / warm-below band behind the pad chrome. No pitch ladder, no tick marks, no ADI sky box.
4. **One locked look.** No new settings picker, no material family, no Rive / Lottie dependency.
5. **SceneKit primitives at runtime.** No `.usdz`, `.glb`, or network fetch.
6. **Same published pose as today.** `PostureTrackingManager` does not gain fields. Uncalibrated / disconnected still force displayed pitch and roll to `0`.
7. **Stickman is gone.** If SceneKit fails, the pad continues without a figure. Do not fall back to `figure.stand`.
8. **Overlay Warm / Cool / Alert never tint this pad.** Band green / orange / red tints the ellipse, pip, trail, and glass emission only. Wash stays neutral gray.
9. **Menu-bar icon families stay as they are.** This spec does not redesign `MenuBarIcon`.
10. **macOS 14+ and `CMHeadphoneMotionManager` stay the floor.**

---

## Architecture

### What stays

| Object | Role |
| --- | --- |
| `PostureTrackingManager` | Source of truth for pitch, roll, band, thresholds, captions |
| `PostureGaugeView` | Hero stack: pad, coach chip, grace bar. Same public inputs. |
| `AttitudePad` | Canvas chrome: wash, crosshair, ellipse, trail, pip |
| `CoachChip`, `PostureFormatting` | Unchanged |
| Overlay manager, week store, settings | Unchanged |

### What is added

| Object | Responsibility |
| --- | --- |
| `PostureGaugeMapping` | Pure functions for wash offset, wash bank, bust euler, and displayed pose |
| `InstrumentBustView` | `NSViewRepresentable` wrapping one `SCNView`. Builds the primitive bust, applies euler + emission, pauses when off-screen |

`PostureTrackingManager` does not import SceneKit and does not draw.

Suggested layout:

```
PostureGaugeView
  ZStack
    AttitudePad          // Canvas: wash → crosshair → ellipse → trail → pip
    InstrumentBustView   // SceneKit, centered, hit-testing off
  CoachChip
  ProgressView           // leaning / slouching only
```

Popover width stays **360pt**. Pad height stays **188pt**. Bust visual height is **~72pt**.

### Package

`Package.swift` today is an executable-only target. Tests cannot depend on that.

Split a tiny library:

- `AirPostureCore` — `PostureGaugeMapping` only. No AppKit, no SceneKit, no `PostureFormatting` move.
- `AirPosture` executable — existing app sources, depends on `AirPostureCore`.
- `AirPostureMacTests` — mapping tests only, depends on `AirPostureCore`.

Do not move tracker, overlays, or views into the library.

---

## Visual contract

Layers, back to front, clipped to the existing 16pt-rounded pad:

1. **Horizon wash** (Canvas)
2. **Dashed crosshair** (unchanged)
3. **Threshold ellipse** — 2pt stroke plus a short outer glow in the band color. Math and size unchanged.
4. **Trail** — last 8 samples, 10→4pt, opacity 0.35→0.05, oldest first. Reduce Motion: omit.
5. **Pip** — 14pt fill + white halo. Unchanged geometry.
6. **Bust** — SceneKit, dead-center, does not translate.

Idle / uncalibrated / disconnected / tracking paused:

- Displayed pitch and roll are `0`
- Wash centered and level
- Pip at origin
- Ellipse uses secondary color
- Bust faces the camera, dim emission
- Coach chip still shows the existing caption (“—”, “Set a neutral posture…”, etc.)

---

## Mapping

All functions take **displayed** degrees: `isCalibrated && connected ? liveDelta : 0`.

Shared pad constants stay:

- `maxTilt = 30`
- `maxLean = 20`

Pip point (already shipped):

```
xNorm = clamp(roll / maxLean, -1, 1)
yNorm = clamp(-pitch / maxTilt, -1, 1)
```

`PostureGaugeMapping` must expose these so wash and pip cannot drift apart.

### Horizon wash

- Vertical offset equals the pip’s Y offset from pad center (same `yNorm`, same inset).
- Bank angle = `clamp(roll / maxLean, -1, 1) * 18` degrees.
- Draw a tall two-stop vertical gradient (at least 3× pad height) so both bands remain visible after offset. Clip to the rounded pad.
- Opacity **0.15**.
- Colors are fixed, independent of overlay tint and band:
  - Above: `sRGB(0.46, 0.52, 0.60)`
  - Below: `sRGB(0.58, 0.50, 0.42)`
- Reduce Motion: draw the mapped pose immediately. Do not animate the wash.

### Bust rotation

Reuse the old stickman clamps so a hard slouch does not invert the head:

```
pitchVisual = clamp(pitch, -28, 16) * 0.55
rollVisual  = clamp(roll,  -24, 24) * 0.45
```

Camera: on `+Z`, looking at the origin. Head faces `+Z` (toward camera).

User-visible rules:

- Negative `pitchDelta` is chin-down. That must move the chin toward the chest (top of the head toward the camera).
- Positive `rollDelta` is lean-right (pip moves right). The bust must tip toward the right side of the pad.

Locked conversion (SceneKit radians):

```
eulerX = -pitchVisual * π/180
eulerY = -yawVisual * π/180   // optional; 0 when Show head turn is off
eulerZ = -rollVisual * π/180
```

Positive `yawDelta` (look right) must turn the bust toward the right side of the pad (same side as positive lean).

Set euler angles directly on the bust root each `updateNSView`. Do not use `SCNAction`, springs, or implicit `CATransaction` animation. Reduce Motion therefore needs no extra branch for rotation besides “values are already snapped because the tracker published them.”

### Glass emission

| Band | Emission |
| --- | --- |
| `.upright` | system green, intensity 0.35 |
| `.leaning` | system orange, intensity 0.40 |
| `.slouching` | system red, intensity 0.45 |
| `.paused`, `.uncalibrated`, `.waitingForHeadphones` | white at intensity 0.08 |

Snap on band change. Do not cross-fade through rainbow.

---

## InstrumentBustView

`NSViewRepresentable` → one `SCNView`.

Required configuration:

- `backgroundColor = .clear`
- `isOpaque = false`
- `wantsLayer = true`
- `allowsCameraControl = false`
- `autoenablesDefaultLighting = false` — add two lights: key (upper-left, intensity ~800) and fill (front-dim, intensity ~250)
- Antialiasing: multisampling 4x if the device reports it, else none
- `isPlaying = true` only while the representable is in the hierarchy
- `onDisappear`: `isPlaying = false` so a closed popover does not keep a Metal renderer alive
- SwiftUI wrapper: `.allowsHitTesting(false)` and `.accessibilityHidden(true)`
- The `SCNView` must not become first responder

Bust built once in `makeNSView`:

- Head: sphere, scale `(0.92, 1.0, 0.88)`, smoked glass — `lightingModel = .physicallyBased`, `metalness = 0.18`, `roughness = 0.08`, `transparency = 0.38`, `emission` from the table above
- Neck: short cylinder under the head, `metalness = 0.85`, `roughness = 0.32`, no transparency
- Shoulders: two flattened spheres at the base (`scale (1.1, 0.28, 0.7)` each), same metal as the neck, so they read as a stand, not a torso

Do not load files from disk. Do not add a floor plane, shadow catcher, or environment map that requires an asset catalog HDR.

Coordinator updates on `updateNSView`:

- Apply `eulerX/Y/Z` to the bust root node
- Apply emission to the head material only
- Do not rebuild the scene graph on every frame

If `SCNView` / Metal cannot be created, return an empty clear `NSView` and log once. `AttitudePad` still draws.

---

## AttitudePad changes

Keep the existing frame fill, dashed crosshair, ellipse, trail, and pip.

Add the wash as the first calibrated (and idle) layer inside the rounded clip. Idle still draws the wash at origin so the pad does not go flat gray when uncalibrated.

Ellipse gain: after the 2pt stroke, stroke a second ellipse inset by **-3pt** (outside) at the same band color with opacity **0.22** and line width **6**. That is the “short outer glow.” Reduce Transparency: skip the glow, keep the 2pt ring.

---

## Accessibility

Unchanged from the console spec:

- One VoiceOver element on the gauge container (`accessibilityElement(children: .combine)`)
- Value: caption + signed tilt + signed lean
- Chip, wash, pip, trail, and bust are `accessibilityHidden`
- No new buttons or focusable SceneKit hits

---

## Error handling

| Condition | Behavior |
| --- | --- |
| SceneKit / Metal unavailable | Hide bust. Pad + wash + pip remain. No stickman. |
| Popover closed | Pause `SCNView`. |
| Headphones drop, tracking paused, uncalibrated | Displayed pose `0`. Idle visual contract above. |
| Reduce Motion | Snap wash and bust. No trail. |
| Reduce Transparency | Drop ellipse glow. Do not flatten the glass into an SF Symbol. |
| Focus / snooze / overlay | Irrelevant to this spec. Existing overlay rules stand. |

---

## Testing

`AirPostureMacTests` covers `PostureGaugeMapping` only. No GPU snapshot tests.

Required cases:

1. Zero pose → wash offset 0, bank 0, euler 0, pip at center.
2. Uncalibrated flag → treat as zero even if raw deltas are non-zero (the flag is applied before mapping; test `displayedPose` helper).
3. Pitch `−28` and `+16` sit on the clamp edges; `−40` and `+30` do not exceed them.
4. Roll `±24` sit on the clamp edges; `±40` do not exceed them.
5. Chin-down (negative pitch) → `eulerX > 0` with the locked conversion.
6. Positive roll → pip X `>` center, `eulerZ < 0`.
7. Wash bank at `roll = maxLean` is `+18°`; beyond that it stays `±18°`.
8. Wash Y offset matches pip Y for the same pitch.

Manual check (not automated):

- Open the popover, slouch, sit up: bust rotates, pip travels, wash banks, ellipse goes green → orange → red.
- Enable Reduce Motion: trail disappears; wash and bust jump.
- Quit while the popover is open: app exits cleanly.
- Disconnect AirPods: idle contract.

---

## Implementation order

1. `AirPostureCore` + `PostureGaugeMapping` + tests (red, then green).
2. Horizon wash + ellipse glow in `AttitudePad`.
3. Remove the SF Symbol overlay.
4. `InstrumentBustView` with a static facing bust (no rotation).
5. Wire euler + emission.
6. Pause on disappear; SceneKit-failure fallback.
7. Manual pass of the checklist above.

---

## Out of scope

- Memoji, Animoji, AvatarKit, Contacts avatars
- User photo or emoji as the token
- Downloaded or bundled mesh files
- Rive / Lottie
- Traveling bust
- Full attitude HUD (horizon ladder, ticks, sky box)
- New Options picker for materials or figure style
- Menu-bar icon redesign
- Changes to overlay styles, week analytics, Desk/Sofa, ellipse math, grace, or sounds

---

## Precedence

If this file and `2026-09-05-airposture-console-overlays-analytics-design.md` disagree about the seated/stand figure, this file wins. If they disagree about anything else, the console spec wins.
