# AirPosture avatar assets

The active avatar is an upper-body derivative of the **user-supplied Coolio 2.0
UPDATED.blend**. `CoolioBust.blend` is the editable, simplified source;
`Sources/AirPostureMac/Resources/AirPostureBust.usdz` is the bundled runtime
export. The original file in Downloads is never modified.

Source SHA-256: `826496e4f4721c7e103356021ba45fe457cd4410fdfc483a17f6e2543438aa52`.
The supplied model's existing ownership/license terms still apply. This
Coolio derivative is not the CC0 Blender Human Base Mesh used by the previous
avatar. The older `AirPostureBust.blend` and `build_airposture_bust.py` are
retained as historical assets, not the current build pipeline.

## Rebuild

From the repository root:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --disable-autoexec '/path/to/Coolio 2.0 UPDATED.blend' \
  --python Tools/Blender/build_coolio_bust.py
```

This reads base geometry only, crops and caps the hips, poses the original arms
and hands loosely beside the torso, modestly enlarges the head, adds black brows, and builds a
small deformation rig. Embedded source scripts, lattice controls, animation
drivers, and the full-body rig are not copied into the result. The runtime
asset has no textures, network dependencies, lights, cameras, or baked loops.
Export size and geometry counts are in `CoolioBust-metrics.json`.

## Rig contract

The model is 2 units high, centered vertically at zero. Exported coordinates
are +Y up and +Z forward, facing the SceneKit camera. All joints are named:

```
CTRL_root
└── CTRL_chest
    ├── CTRL_shoulderLeft
    │   └── CTRL_elbowLeft
    │       └── CTRL_wristLeft
    ├── CTRL_shoulderRight
    │   └── CTRL_elbowRight
    │       └── CTRL_wristRight
    └── CTRL_neck
        └── CTRL_head
            ├── CTRL_eyeLeft / CTRL_eyeRight
            ├── CTRL_browLeft / CTRL_browRight
            └── CTRL_mouthLeft / CTRL_mouthRight
```

Left/right mean anatomical sides: left is +X (screen right). Head and facial
geometry remain rigid outside the neck transition and the small mouth-corner
weight regions. Shoulder weights blend into the chest, with smooth transitions
at the elbows and wrists. Hands keep the original finger topology and use one rigid wrist
control per side. Hips anchor the root.
Eyes and brows have independent joints for blinks and quiet expressions.

The renderer preserves imported bind/rest transforms and applies processed
animation deltas. The visual processor mirrors yaw and roll, including inferred
shoulder/arm asymmetry; pitch and published tracker values stay unchanged.
Tracking provides headphone pitch, roll, yaw, and posture status only: chest
motion and shoulder asymmetry are inferred illustrations,
not independent torso or shoulder measurements.

## Tuning and verification

`BustAnimationConfig` in AirPostureCore holds animation tuning. In Debug builds,
launch with `AIRPOSTURE_BUST_DEBUG=1` to show a tuning button beside the avatar, with live controls and input/processed/
bone diagnostics in its development popover. Release builds omit this UI. Posture
expressions follow the existing band, so preset, sensitivity, and grace-period
settings retain their current meanings. Brief eyebrow raises acknowledge band
changes; returning upright after a slouch also opens the arms slightly. Gestures
finish within 0.72 seconds, observe a 2-second cooldown, and do not restart for
every tracking sample. The Gestures
slider controls this extra motion; Reduce Motion disables transient gestures.

The native render fixture checks the actual USDZ through the production
SceneKit rig. Its snapshots cover neutral, head movement, slouch, side lean,
blink, concern, recovery gestures and inactive state at 328×188 points, including Retina output. Use the
fixture together with the pure animation checks; a Blender preview alone
does not verify SceneKit's skeleton import.

Verification commands:

```bash
make test                         # Pure animation plus existing app checks
Tests/run-bust-render-checks.sh    # GPU-backed offscreen snapshots and timing
Tests/run-bust-lifecycle-checks.sh # Brief native window; auto-exits after checks
AIRPOSTURE_BUST_DEBUG=1 Tests/run-bust-lifecycle-checks.sh --interactive
```

The interactive fixture uses simulated angles and does not instantiate the
tracker. Close its window to exit. GPU-backed checks need access to the local
window server/Metal device; restrictive sandboxes may prevent them from running.
