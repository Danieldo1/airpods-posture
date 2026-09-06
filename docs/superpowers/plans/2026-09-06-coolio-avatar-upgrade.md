# Coolio Avatar Upgrade Implementation Plan

**Goal:** Implement the user's supplied avatar upgrade plan with the attached Coolio model, torso through hips, black eyes/brows, and expressions driven by existing posture status.

**Architecture inspected before changes:** SwiftUI `PostureGaugeView` owns a 188pt-high SceneKit hero inside a 360pt popover. `InstrumentBustView` imports `AirPostureBust.usdz`, discovers `CTRL_chest`, `CTRL_neck`, `CTRL_head`, and updates neck/head using a 75ms SCNTransaction. Chest is currently static. Eye actions blink independently. `PostureTrackingManager` publishes calibrated pitch/roll degrees and session-relative yaw, pre-smoothed with alpha 0.4. Negative pitch means chin down; positive roll means pad-right. Existing normalized data: gauge x=roll/20 and y=-pitch/30 clamped ±1; normalizedDeviation=deviation/threshold (unbounded positive); slouchProgressClamped 0...1; discrete postureBand honors selected preset, sensitivity and grace period. No actual chest/shoulder or face measurements exist. Tracking is unchanged.

**Tech stack:** macOS 14+, SwiftUI, SceneKit, pure Swift animation processing, Blender USDZ export.

**Constraints:** Work on main; no commits; no dev server. Preserve unrelated uncommitted changes. Use Coolio supplied by user, not old CC0 bust. Preserve tracking/settings/scoring. Body and shoulder motion is inferred visualization, not independently measured. Keep 188pt hero and 360pt popover. No runtime network dependencies.

## Tasks

- [x] Inspect current architecture and supplied file with embedded script auto-execution disabled.
- [x] Build an optimized editable Coolio derivative with capped hips, no legs, enlarged head, black eyes/eyebrows and six posture controls. Remove production rig constraints/drivers and retain soft neck/shoulder skinning.
- [x] Add pure `BustTrackingPose`, `BustAnimationConfig`, processor and rig output in AirPostureCore. Use frame-rate-independent smoothing, hysteresis dead zones, bounded amplification, 30/70 neck/head split, inferred chest/shoulder offsets, additive idle/breath/blink, and posture expression state. Verify directions, limits, settling, noise suppression, idle preservation, inactive/reduce-motion and timing.
- [x] Bind cached rig nodes to the renderer's update callback (30fps), with a synchronized input mailbox. Pause when hidden/detached; eliminate static active-view ownership and per-update actions. Preserve transforms relative to rest pose.
- [x] Add opt-in DEBUG-only live sliders and raw/processed/bone readouts, isolated from release UI.
- [x] Verify USDZ rig deformation and front-facing axes using actual SceneKit snapshots at popover resolution. Inspect extremes and expressions. Build Debug/Release, run existing checks, measure frame processing and render cost, document real limitations.

## Verification commands

Use native Swift check executables and `swift build --disable-sandbox --cache-path /tmp/airposture-swiftpm/cache --config-path /tmp/airposture-swiftpm/config --security-path /tmp/airposture-swiftpm/security`. Run the existing mapping/feature and native tracking/store checks. A native snapshot fixture loads the production scene and exercises the rig; Blender previews alone are insufficient. Test processor changes with independent behavioral assertions before implementation.

## Decisions

User's detailed implementation request supplies scope/design authorization; proceed incrementally without further design approval. Existing documents describe the previous asset and are historical, not instructions overriding the current request. Upper body asymmetry is inferred from roll because AirPods cannot measure shoulders separately. Preserve unknown source licensing metadata rather than relabeling Coolio as CC0.

## Completed verification

- Pure animation: native Swift, Swift 6 strict concurrency, and SwiftPM checks pass. Tests cover signs, clamping, 30/60fps held and moving targets, hysteresis at nonzero posture, settling, invalid data, additive idle, blinking, expressions, inactive and Reduce Motion. A fixed-frame timing mutation fails the moving-target test.
- Existing `make test` checks pass: feature/scoring, legacy mapping, settings, sound policy, and tracking/analytics store. Intentional failure diagnostics in the native harness are expected.
- Debug and Release `.app` bundles build and sign locally. Release binary contains no tuning launch flag or debug-panel strings. Bundled USDZ SHA-256 matches the source asset.
- Production SceneKit snapshots at 328×188pt @2x pass all direction and clipping checks. Neutral model height is156pt; twelve cases include both yaw directions, side leans, slouch, chin-up, combined extremes, concern, blink and inactive. Visual review confirms black eyes, seated brows, smile/frown and closed-eye blink.
- Native lifecycle: all11 checks pass (visible playback, scene reuse, renderer-driven pose, scroll-away pause, scroll-back resume, hidden-window pause, visible-window resume, removed-view pause, recreated-view resume, old-view isolation, closed-window stop).
- Live DEBUG panel tested through native UI: yaw1.5→1.7, idle1→0 suppresses idle head transforms, Reset restores defaults; tracker/processed/final bone readout updates.
- Final asset:633,771bytes,5,862vertices,11,596triangles,8meshes,12joints. No source drivers, scripts, full-body skeleton, legs, textures, lights or cameras exported.
- Native visible fixture sampled2.54% of one CPU core over2seconds. Animation plus12-joint apply averaged0.0073ms/frame over10,000iterations. Offscreen Retina render including readback: median1.07ms,p951.96ms (30samples). Measurements are machine-specific; they do not establish long-term energy use or total live AirPods application cost.
- Independent scoped review: no remaining actionable findings. Fixed eye winding, brow seating, undersized/overexposed rendering, and scroll/close playback found during verification.

## Remaining practical limits

Actual AirPods feel needs local hardware testing. Chest and shoulder asymmetry are inferred from headphone attitude because no separate torso/shoulder measurements exist. Multi-axis neck/head decomposition preserves the intended summed Euler attitude; it is not an anatomical simulation or quaternion-exact decomposition. Original Coolio ownership terms remain in force; no license is invented.

No commits, branches, server startup, tracking algorithm changes, or unrelated application rewrites were made.
