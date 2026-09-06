# Instrument Bust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hero-gauge SF Symbol stickman and diagram chrome with a large centered SceneKit titanium-ceramic bust.

**Architecture:** Pure mapping lives in a new `AirPostureCore` library so tests can run without AppKit. `PostureGaugeView` presents the full-size bust directly, followed by the coach chip and reserved grace bar. `InstrumentBustView` loads a bundled, Blender-authored USDZ and drives its named bones. `PostureTrackingManager` is unchanged.

> **Revision 2026-09-06:** The earlier `AttitudePad` task is superseded. The rounded chart frame, threshold ellipse, dot, trail, wash, crosshair, and gridlines are removed; the bust is scaled to fill most of the same 188pt hero area.

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI, SceneKit, XCTest, Swift Package Manager (`./build.sh` is the app build).

## Global Constraints

- macOS 14+, bundle `com.macposture.airposture`, accessory `MenuBarExtra` only
- Public AppKit / SwiftUI / SceneKit only — no AvatarKit and no runtime model downloads
- Motion data never leaves the Mac
- Hero 188pt, popover 360pt, bust ~157pt at root scale 1.35, one locked look
- Stickman and attitude diagram are gone; SceneKit failure → coach chip and grace bar only
- Overlay Warm/Cool/Alert never tint this pad
- This spec supersedes only the seated/stand figure line; console spec wins on everything else
- Frequent commits are optional here: the user asked to implement, not to commit each task

---

## File map

- Create: `Sources/AirPostureCore/PostureGaugeMapping.swift`
- Create: `Tests/AirPostureMacTests/PostureGaugeMappingTests.swift`
- Create: `Sources/AirPostureMac/InstrumentBustView.swift`
- Create: `Sources/AirPostureMac/Resources/AirPostureBust.usdz`
- Create: `DesignAssets/AirPostureBust.blend`
- Create: `Tools/Blender/build_airposture_bust.py`
- Modify: `Package.swift`
- Modify: `Sources/AirPostureMac/PostureGaugeView.swift`
- Modify: `AirPostureMac.xcodeproj/project.pbxproj`
- Do not modify: tracker, overlays, week store, settings, menu-bar icons

---

### Task 1: Mapping library + failing tests

**Files:**
- Create: `Sources/AirPostureCore/PostureGaugeMapping.swift`
- Create: `Tests/AirPostureMacTests/PostureGaugeMappingTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: nothing
- Produces:

```swift
public enum PostureGaugeMapping {
    public static let maxTilt: Double
    public static let maxLean: Double
    public static func displayedPose(pitch: Double, roll: Double, isCalibrated: Bool) -> (pitch: Double, roll: Double)
    public static func normalizedPoint(pitch: Double, roll: Double) -> (x: Double, y: Double)
    public static func washBankDegrees(roll: Double) -> Double
    public static func pitchVisualDegrees(_ pitch: Double) -> Double
    public static func rollVisualDegrees(_ roll: Double) -> Double
    public static func bustEulerRadians(pitch: Double, roll: Double) -> (x: Double, y: Double, z: Double)
}
```

- [ ] **Step 1: Split the package**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirPostureMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AirPosture", targets: ["AirPosture"]),
        .library(name: "AirPostureCore", targets: ["AirPostureCore"])
    ],
    targets: [
        .target(
            name: "AirPostureCore",
            path: "Sources/AirPostureCore"
        ),
        .executableTarget(
            name: "AirPosture",
            dependencies: ["AirPostureCore"],
            path: "Sources/AirPostureMac"
        ),
        .executableTarget(
            name: "AirPostureMappingCheck",
            dependencies: ["AirPostureCore"],
            path: "Tests/AirPostureMappingCheck"
        )
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Put the eight spec cases in `PostureGaugeMappingTests.swift`. Use `XCTAssertEqual` with `accuracy: 0.0001`.

- [ ] **Step 3: Run tests and confirm they fail**

Run: `swift test --disable-sandbox --filter PostureGaugeMappingTests`

Expected: FAIL because `PostureGaugeMapping` is missing or returns zeros.

- [ ] **Step 4: Implement `PostureGaugeMapping`**

Lock the formulas from the spec:

```
displayed = isCalibrated ? (pitch, roll) : (0, 0)
xNorm = clamp(roll / 20, -1, 1)
yNorm = clamp(-pitch / 30, -1, 1)
washBank = xNorm * 18
pitchVisual = clamp(pitch, -30, 20) * 0.70
rollVisual  = clamp(roll,  -24, 24) * 0.45
eulerX = -pitchVisual * π/180
eulerY = 0
eulerZ = -rollVisual * π/180
```

- [ ] **Step 5: Run tests and confirm they pass**

Run: `swift test --disable-sandbox --filter PostureGaugeMappingTests`

Expected: PASS

---

### Task 2: Horizon wash + ellipse glow

**Files:**
- Modify: `Sources/AirPostureMac/PostureGaugeView.swift`

**Interfaces:**
- Consumes: `PostureGaugeMapping.normalizedPoint`, `washBankDegrees`, `displayedPose`
- Produces: Canvas layers wash → crosshair → ellipse+glow → trail → pip

- [ ] **Step 1: Drive displayed pose from the mapping**

```swift
import AirPostureCore

private var displayedPose: (pitch: Double, roll: Double) {
    PostureGaugeMapping.displayedPose(
        pitch: pitchDelta,
        roll: rollDelta,
        isCalibrated: isCalibrated
    )
}
```

Remove `figureName`, `figurePitch`, `figureRoll`, and the `Image(systemName:)` overlay.

- [ ] **Step 2: Draw wash and glow in `AttitudePad`**

- Read `@Environment(\.accessibilityReduceTransparency)`
- Always draw the wash (idle at origin)
- Wash: clip to 16pt rounded pad, translate by pip Y, rotate by `washBankDegrees`, fill a rect ≥ 3× pad height with opacity 0.15, above `sRGB(0.46, 0.52, 0.60)`, below `sRGB(0.58, 0.50, 0.42)`
- Pip and trail use `PostureGaugeMapping.normalizedPoint` so they cannot drift from the wash
- Ellipse always drawn; secondary when not calibrated or idle bands
- Glow: second stroke inset by -3pt, width 6, opacity 0.22, skipped when Reduce Transparency is on
- Constants `maxTilt` / `maxLean` come from the mapping, not local duplicates

---

### Task 3: SceneKit bust

**Files:**
- Create: `Sources/AirPostureMac/InstrumentBustView.swift`
- Modify: `Sources/AirPostureMac/PostureGaugeView.swift`
- Modify: `AirPostureMac.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `PostureGaugeMapping.bustEulerRadians`, `PostureBand`
- Produces: `InstrumentBustView(pitch:roll:band:)`

- [ ] **Step 1: Build `InstrumentBustView`**

`NSViewRepresentable` → subclassed `SCNView` with `acceptsFirstResponder = false`.

Scene (once in `makeNSView`):

- Load `AirPostureBust.usdz` from the application bundle
- Camera on +Z, orthographic scale 1.55; turn the Y-up imported model to face +Z and scale it to 1.35
- Resolve `CTRL_neck` and `CTRL_head`; store their rest positions
- Keep the cranium/face rigid on `CTRL_head`, blend only the lower neck, and use a front-aware jaw mask
- Give the head 65% of pitch and the neck 35%; use only restrained forward offsets and no vertical bone translation
- Rigid-skin both eye meshes to `CTRL_head`; drive one synchronized randomized blink action and disable it under Reduce Motion
- Replace the imported `Porcelain`, `Graphite`, and `StatusGlow` materials with native SceneKit PBR materials
- Key light upper-left intensity 100, fill front intensity 35, cool rim intensity 60
- `autoenablesDefaultLighting = false`, clear background, no camera control
- Antialiasing 4x when available

`updateNSView`: split mapped euler and slouch offset across the neck/head bones; set subtle ceramic emission plus the stronger collar emission; do not rebuild the graph.

`onDisappear`: `isPlaying = false`. SwiftUI: `.allowsHitTesting(false)` `.accessibilityHidden(true)` `.frame(height: 188)`.

Emission follows the ceramic/collar intensity table in the design spec.

If `SCNView` cannot be created, return a clear `NSView` and log once.

- [ ] **Step 2: Compose in `PostureGaugeView`**

```swift
ZStack {
    AttitudePad(...)
        .frame(height: 188)
    InstrumentBustView(pitch: displayedPose.pitch, roll: displayedPose.roll, band: band)
        .frame(height: 188)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
}
```

- [ ] **Step 3: Register new files in the Xcode project**

Add `PostureGaugeMapping.swift` and `InstrumentBustView.swift` to the AirPosture sources build phase so the xcodeproj stays in sync with SPM.

- [ ] **Step 4: Build**

Run: `swift test --disable-sandbox` then `./build.sh debug`

Expected: tests pass, app bundle builds.

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| Mapping formulas + tests 1–8 | Task 1 |
| Horizon wash, ellipse glow, Reduce Transparency | Task 2 |
| Stickman removed, pip/trail unchanged | Task 2 |
| InstrumentBustView, euler, emission, pause, fallback | Task 3 |
| VoiceOver unchanged | Task 2 (no new VO targets) |
| Package split | Task 1 |
| Out of scope (Memoji, overlays, icons) | not implemented |
