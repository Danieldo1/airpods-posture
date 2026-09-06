# AirPosture instrument bust

Design spec for replacing the hero-gauge stickman and attitude diagram with a centered, rigged titanium-ceramic bust. Implementation must follow this document.

**Status:** revised and approved
**Date:** 2026-09-05  
**Platform:** macOS 14+, SwiftUI `MenuBarExtra` with `.window` style, accessory app  
**Bundle ID:** `com.macposture.airposture`

This spec **supersedes** only one line in `2026-09-05-airposture-console-overlays-analytics-design.md`:

> Keep the seated/stand figure overlay, slightly larger (30pt).

Every other non-hero decision in that document stays in force: 188pt hero height, coach chip, grace bar, VoiceOver combine, overlays, week store, scoring ellipse math, and menu-bar icon families. The visible threshold ellipse, pip, trail, wash, frame, and gridlines are retired.

---

## Problem

The console already reads as an instrument: ellipse, crosshair, pip, trail. The SF Symbol on top (`figure.stand` / `figure.seated.side`) does not. It is both a traveling token and a person, and it makes the pad look like a toy.

Users want a presence that feels like an Apple object, not a cartoon, while keeping the bound as the “am I inside?” read.

Constraints that stay non-negotiable:

- Menu-bar popover only. No extra window, no Dock HUD.
- Public AppKit / SwiftUI / SceneKit only. No AvatarKit, no Memoji, no private frameworks.
- Motion data never leaves the Mac. The model is bundled with the app; there are no runtime downloads.
- AirPods give pitch and roll. Optional session-relative yaw may rotate the bust and gate scoring when looking aside; it still does not join the tilt/lean ellipse. No camera face capture or blend shapes.
- Reduce Motion must snap pose changes and disable the periodic eye blink.

---

## Decisions

These are locked. If a later idea conflicts with this list, this list wins.

1. **Large centered bust, no attitude plot.** The sculpture fills most of the 188pt hero height and only rotates/deforms. Do not draw a chart frame, threshold ellipse, marker dot, trail, wash, crosshair, or gridlines.
2. **Sculptural person, not a white stickman.** Use the faceted head/neck/clavicle bust derived from Blender's CC0 Human Base Meshes bundle. Titanium-ceramic facets, graphite eye insets and plinth, and one narrow status collar. No hair, skin-tone picker, photo mapping, or photoreal skin.
3. **Quiet transparent stage.** The SceneKit view sits directly in the hero area with no decorative diagram chrome behind it.
4. **One locked look.** No new settings picker, no material family, no Rive / Lottie dependency.
5. **Editable Blender source, bundled USDZ at runtime.** Keep `DesignAssets/AirPostureBust.blend` with `CTRL_chest`, `CTRL_neck`, and `CTRL_head`; ship the optimized `AirPostureBust.usdz`. No network fetch.
6. **Same published pose as today.** `PostureTrackingManager` does not gain fields. Uncalibrated / disconnected still force displayed pitch and roll to `0`.
7. **Stickman is gone.** If SceneKit fails, the pad continues without a figure. Do not fall back to `figure.stand`.
8. **Overlay Warm / Cool / Alert never tint this view.** Band green / orange / red affects only the subtle ceramic emission and status collar.
9. **Menu-bar icon families stay as they are.** This spec does not redesign `MenuBarIcon`.
10. **macOS 14+ and `CMHeadphoneMotionManager` stay the floor.**

---

## Architecture

### What stays

| Object | Role |
| --- | --- |
| `PostureTrackingManager` | Source of truth for pitch, roll, band, thresholds, captions |
| `PostureGaugeView` | Hero stack: pad, coach chip, grace bar. Same public inputs. |
| `CoachChip`, `PostureFormatting` | Unchanged |
| Overlay manager, week store, settings | Unchanged |

### What is added

| Object | Responsibility |
| --- | --- |
| `PostureGaugeMapping` | Pure functions for wash offset, wash bank, bust euler, and displayed pose |
| `InstrumentBustView` | `NSViewRepresentable` wrapping one `SCNView`. Loads the bundled rigged bust, applies bone euler + emission, pauses when off-screen |

`PostureTrackingManager` does not import SceneKit and does not draw.

Suggested layout:

```
PostureGaugeView
  InstrumentBustView     // SceneKit, large, centered, hit-testing off
  CoachChip
  ProgressView           // leaning / slouching only
```

Popover width stays **360pt**. Hero height stays **188pt**. Bust visual height is approximately **157pt**.

### Package

`Package.swift` today is an executable-only target. Tests cannot depend on that.

Split a tiny library:

- `AirPostureCore` — `PostureGaugeMapping` only. No AppKit, no SceneKit, no `PostureFormatting` move.
- `AirPosture` executable — existing app sources, depends on `AirPostureCore`.
- `AirPostureMacTests` — mapping tests only, depends on `AirPostureCore`.

Do not move tracker, overlays, or views into the library.

---

## Visual contract

The 188pt hero is a transparent, uninterrupted sculpture stage:

1. **Bust** — SceneKit, dead-center, scaled to `1.35`, with the head, clavicle, collar, and plinth clearly readable.
2. **Nothing behind it** — no rounded square, ellipse, marker dot, trail, wash, crosshair, or gridlines.
3. **No replacement decoration** — the larger figure and its lighting provide the hierarchy.

Idle / uncalibrated / disconnected / tracking paused:

- Displayed pitch and roll are `0`
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

These helpers remain tested for compatibility, but the bust-only hero does not render a wash or pip.

### Retired diagram mapping

`normalizedPoint` and `washBankDegrees` may remain in `AirPostureCore` while older mapping checks depend on them. `PostureGaugeView` must not call them or run a trail sampling task.

### Bust rotation

Use asymmetric anatomical clamps so chin-down is clearly readable without
inverting the head, while chin-up remains restrained:

```
pitchVisual = clamp(pitch, -30, 20) * 0.70
rollVisual  = clamp(roll,  -24, 24) * 0.45
```

Camera: on `+Z`, looking at the origin. Head faces `+Z` (toward camera). Imported root scale is `1.35`.

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

Split euler angles between `CTRL_neck` and `CTRL_head` each `updateNSView`. The
head receives 65% of pitch and the neck receives 35%; this creates a readable
nod while keeping the shoulders planted. At maximum chin-down, translate the
neck and head forward only `0.015` and `0.025` model units respectively. Do not
translate either bone vertically—the rotation itself lowers the chin, while a
vertical bone offset stretches the facial transition. Do not use `SCNAction`
or springs for posture pose updates. Reduce Motion uses a zero-duration
`SCNTransaction`; ordinary tracking uses only a short ease-out settle.

### Eye rig and blink

`GraphiteEyeLeft` and `GraphiteEyeRight` are rigid-skinned to `CTRL_head`, with
their object origins centered before export. Head and neck movement must carry
the eyes as one assembled face; no eye may remain behind when the bust turns.

At runtime, both eyes share a quiet repeating blink sequence:

- randomized wait between approximately 2.7 and 4.9 seconds
- 65ms close, 35ms hold, 100ms open
- scale only each eye's local vertical axis around its centered origin
- pause naturally with the `SCNView` when the popover closes
- remove the blink action and restore open eyes when Reduce Motion is enabled

### Bust emission

| Band | Ceramic emission | Collar emission |
| --- | --- | --- |
| `.upright` | system green, intensity 0.055 | system green, intensity 1.25 |
| `.leaning` | system orange, intensity 0.065 | system orange, intensity 1.45 |
| `.slouching` | system red, intensity 0.075 | system red, intensity 1.65 |
| `.paused`, `.uncalibrated`, `.waitingForHeadphones` | white at intensity 0.015 | white at intensity 0.18 |

Snap on band change. Do not cross-fade through rainbow.

---

## InstrumentBustView

`NSViewRepresentable` → one `SCNView`.

Required configuration:

- `backgroundColor = .clear`
- `isOpaque = false`
- `wantsLayer = true`
- `allowsCameraControl = false`
- `autoenablesDefaultLighting = false` — add three restrained lights: key (upper-left, intensity ~100), fill (front-dim, intensity ~35), and cool rim (intensity ~60)
- Antialiasing: multisampling 4x if the device reports it, else none
- `isPlaying = true` only while the representable is in the hierarchy
- `onDisappear`: `isPlaying = false` so a closed popover does not keep a Metal renderer alive
- SwiftUI wrapper: `.allowsHitTesting(false)` and `.accessibilityHidden(true)`
- The `SCNView` must not become first responder

Bust loaded once in `makeNSView` from the application bundle:

- `PorcelainBust`: approximately 2,850 vertices / 5,700 triangles, deliberately flat-shaded so the face remains sculptural at menu-bar scale
- `GraphiteEyeLeft`, `GraphiteEyeRight`, and `GraphitePlinth`: dark PBR graphite
- `StatusCollar`: separate emissive material carrying green / orange / red state
- `AirPostureRig`: `CTRL_chest` → `CTRL_neck` → `CTRL_head`; the skinner must reference all three bones
- Both eye meshes: rigid skin weight `1.0` on `CTRL_head`
- Cranium and face: near-rigid `CTRL_head` weighting, including a front-aware jaw mask; blend deformation stays in the lower neck

Replace imported USD materials with native `SCNMaterial` instances by material name for predictable SceneKit rendering. Do not add a floor plane, shadow catcher, or external environment map.

Coordinator updates on `updateNSView`:

- Apply the mapped euler and slouch offset to the neck/head bones
- Apply subtle emission to the ceramic and the stronger state read to the collar
- Do not rebuild the scene graph on every frame

If `SCNView` / Metal cannot be created, return an empty clear `NSView` and log once. The coach chip and grace bar still draw.

---

## Retired attitude diagram

`AttitudePad`, `TrailSample`, and the 125ms trail task are removed from `PostureGaugeView`. Thresholds continue to affect posture scoring in `PostureTrackingManager`; they are simply no longer drawn in the hero.

---

## Accessibility

Unchanged from the console spec:

- One VoiceOver element on the gauge container (`accessibilityElement(children: .combine)`)
- Value: caption + signed tilt + signed lean
- Chip and bust are `accessibilityHidden`
- No new buttons or focusable SceneKit hits

---

## Error handling

| Condition | Behavior |
| --- | --- |
| SceneKit / Metal unavailable | Hide bust; keep the coach chip and grace bar. No stickman fallback. |
| Popover closed | Pause `SCNView`. |
| Headphones drop, tracking paused, uncalibrated | Displayed pose `0`. Idle visual contract above. |
| Reduce Motion | Snap bust pose changes; stop blinking and leave both eyes open. |
| Reduce Transparency | No special hero treatment is needed. |
| Focus / snooze / overlay | Irrelevant to this spec. Existing overlay rules stand. |

---

## Testing

`AirPostureMacTests` covers `PostureGaugeMapping` only. No GPU snapshot tests.

Required cases:

1. Zero pose → wash offset 0, bank 0, euler 0, pip at center.
2. Uncalibrated flag → treat as zero even if raw deltas are non-zero (the flag is applied before mapping; test `displayedPose` helper).
3. Pitch `−30` and `+20` sit on the clamp edges; `−40` and `+30` do not exceed them.
4. Roll `±24` sit on the clamp edges; `±40` do not exceed them.
5. Chin-down (negative pitch) → `eulerX > 0` with the locked conversion.
6. Positive roll → pip X `>` center, `eulerZ < 0`.
7. Wash bank at `roll = maxLean` is `+18°`; beyond that it stays `±18°`.
8. Wash Y offset matches pip Y for the same pitch.

Manual check (not automated):

- Open the popover, slouch, sit up: the enlarged bust deforms and its collar goes green → orange → red.
- Compare maximum chin-down and chin-up: the skull and jaw keep their proportions while the neck bends.
- Confirm there is no rounded diagram frame, ellipse, dot, trail, wash, crosshair, or gridline.
- Turn the bust in both directions: the eyes remain seated in the head.
- Watch through several idle intervals: the eyes blink together without jumping.
- Enable Reduce Motion: bust pose changes snap and the eyes remain open.
- Quit while the popover is open: app exits cleanly.
- Disconnect AirPods: idle contract.

---

## Implementation order

1. `AirPostureCore` + `PostureGaugeMapping` + tests (red, then green).
2. Remove the SF Symbol and attitude diagram.
3. `InstrumentBustView` with a static facing bust (no rotation).
4. Wire bone euler + emission.
5. Scale the imported root to `1.35` for the full-size stage.
6. Pause on disappear; SceneKit-failure fallback.
7. Manual pass of the checklist above.

---

## Out of scope

- Memoji, Animoji, AvatarKit, Contacts avatars
- User photo or emoji as the token
- Runtime model downloads or user-selectable avatar libraries
- Rive / Lottie
- Traveling bust
- Full attitude HUD (horizon ladder, ticks, sky box)
- New Options picker for materials or figure style
- Menu-bar icon redesign
- Changes to overlay styles, week analytics, Desk/Sofa, ellipse math, grace, or sounds

---

## Precedence

If this file and `2026-09-05-airposture-console-overlays-analytics-design.md` disagree about the seated/stand figure, this file wins. If they disagree about anything else, the console spec wins.
