# Coolio arms and mirror correction

User follow-up: fix opposite lateral tilt so the character acts as a mirror; retain arms/hands for presence; add small arm movement and clearer eyebrow responses. Continue on main without commits or server. Tracking and scoring remain unchanged.

- [x] Correct the animation-only lateral sign convention with failing mirror regressions, including shoulder asymmetry. Reflect both lateral rotation axes together; pitch stays unchanged.
- [x] Restore original Coolio arms and hands, bend them into a relaxed pose at the sides, and retain torso ending at the hips with no legs. Add elbow/wrist controls and weights as needed. Keep a clear silhouette in the existing 188pt hero.
- [x] Add subordinate shoulder/elbow movement and brief eyebrow raises on posture transitions. Use the existing processor/frame loop, respect Reduce Motion and inactive state, and avoid repeated emotes/noisy loops.
- [x] Bind controls, regenerate the source/USDZ, and test actual SceneKit mirrored landmarks, arm deformation, hand visibility, expressions and extreme framing. Re-run affected animation/lifecycle checks and app builds.

The prior tests proved positive input mapped to positive screen direction, not the requested hardware mirror convention. The user's local observation corrects that assumption; reflection belongs in the visual processor only.

## Verification

- Pure animation tests pass, including mirror signs, unmodified measured diagnostics, elbow/wrist output, finite settings, gesture cancellation, 0.72s duration, 2s cooldown, and rapid band chatter. Swift 6 strict concurrency checks pass.
- Native SceneKit fixture passes all 15 poses at 328×188pt / Retina, including mirrored facial/shoulder landmarks, hand movement, brow lift, and opposite combined limits. The initial recovery fixture incorrectly used Reduce Motion to arm a gesture; it now observes an active slouch before recovery, preserving the production reset behavior.
- Native lifecycle fixture passes 11 checks with a visible window, including callback direction, cached scene identity, scroll/window/removal pause and resume, and close. An earlier run failed its visible-state checks; added window/view diagnostics and reran successfully without production changes. Visible fixture CPU sampled 2.24% of one core over 2 seconds; this short sample is not a sustained energy profile.
- Model: 16 controls, 36,740 triangles, 2,049,036-byte USDZ. Animation and rig updates measured 0.0102 ms/frame; offscreen render including readback measured 1.09 ms median / 4.56 ms p95 at 656×376. These are bounded fixture measurements, not live GPU utilization.
- `make test` passes existing mapping, settings, sound-policy and analytics checks alongside the new animation checks. Final scoped code review reports no production blockers.
- Debug and Release app builds pass; bundled model hashes match the regenerated asset, Release signing verifies, and development tuning strings are absent from Release. Work stays uncommitted on main.
- Physical AirPods reflection still requires local hardware observation; automated cases verify the corrected sign convention through actual SceneKit joint positions.
