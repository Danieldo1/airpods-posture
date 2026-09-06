# AirPosture bust asset

`AirPostureBust.blend` is the editable source for the figure in the attitude
pad. Its three pose controls are named `CTRL_chest`, `CTRL_neck`, and
`CTRL_head`. The application drives the neck and head controls at runtime.
Both graphite eye meshes are rigid-skinned to `CTRL_head`, so they follow the
head pose while remaining independently scalable for the blink animation.
The cranium, face, and front of the jaw are likewise carried by `CTRL_head` as
a near-rigid unit. Deformation is confined to the lower neck transition so an
up/down nod does not compress the face.

The mesh is derived from **Head (Animation) – Realistic** in Blender's
[Human Base Meshes bundle](https://www.blender.org/download/demo-files/),
version 1.4.1. Blender publishes the bundle under CC0; the derivative files in
this directory and the generated USDZ may therefore be modified and shipped
with the application.

The app does not fetch a model or texture from the network. The optimized
`AirPostureBust.usdz` is bundled in `Sources/AirPostureMac/Resources`.

To rebuild all generated files, open a shell at the repository root and run:

```bash
/Applications/Blender.app/Contents/MacOS/Blender \
  --background /path/to/human_base_meshes_bundle.blend \
  --python Tools/Blender/build_airposture_bust.py
```

The script deliberately produces a medium-poly faceted surface, graphite eye
insets and plinth, and a separate emissive status collar. Keep material and
control names stable because `InstrumentBustView` discovers them by name.
