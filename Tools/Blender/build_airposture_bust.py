"""Build the editable and runtime AirPosture bust assets.

Run with Blender, using the official Blender Human Base Meshes bundle as the
input file:

    Blender --background human_base_meshes_bundle.blend \
        --python Tools/Blender/build_airposture_bust.py

The script deliberately keeps the source asset small and deterministic. The
resulting .blend contains a three-control rig; the USDZ contains only the rig,
the skinned bust, the graphite eyes, plinth, and status collar.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DESIGN_ASSET_DIR = PROJECT_ROOT / "DesignAssets"
RUNTIME_ASSET_DIR = PROJECT_ROOT / "Sources" / "AirPostureMac" / "Resources"
BLEND_PATH = DESIGN_ASSET_DIR / "AirPostureBust.blend"
PREVIEW_PATH = DESIGN_ASSET_DIR / "AirPostureBust-preview.png"
USDZ_PATH = RUNTIME_ASSET_DIR / "AirPostureBust.usdz"

SOURCE_BUST = "GEO-head_animation_realistic"
SOURCE_EYES = (
    "GEO-head_animation_realistic.sclera.L",
    "GEO-head_animation_realistic.sclera.R",
)


def evaluated_copy(source_name: str, output_name: str) -> bpy.types.Object:
    source = bpy.data.objects[source_name]
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
    result = bpy.data.objects.new(output_name, mesh)
    bpy.context.scene.collection.objects.link(result)
    result.matrix_world = source.matrix_world.copy()

    bpy.ops.object.select_all(action="DESELECT")
    result.select_set(True)
    bpy.context.view_layer.objects.active = result
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return result


def remove_original_library_objects(keep: set[bpy.types.Object]) -> None:
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)


def normalize_objects(objects: list[bpy.types.Object], bust: bpy.types.Object) -> None:
    world_points = [bust.matrix_world @ vertex.co for vertex in bust.data.vertices]
    minimum = Vector(tuple(min(point[index] for point in world_points) for index in range(3)))
    maximum = Vector(tuple(max(point[index] for point in world_points) for index in range(3)))
    center = (minimum + maximum) * 0.5
    scale = 2.0 / (maximum.z - minimum.z)

    # The sculpture is two Blender units tall, centered vertically around zero.
    # All source objects share the same original coordinate system.
    for obj in objects:
        for vertex in obj.data.vertices:
            world = obj.matrix_world @ vertex.co
            vertex.co = Vector(
                (
                    (world.x - center.x) * scale,
                    (world.y - center.y) * scale,
                    (world.z - center.z) * scale,
                )
            )
        obj.matrix_world.identity()


def center_object_origin(obj: bpy.types.Object) -> None:
    center = sum((vertex.co for vertex in obj.data.vertices), Vector()) / len(obj.data.vertices)
    for vertex in obj.data.vertices:
        vertex.co -= center
    obj.location = center


def make_material(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    emission_color: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    material.diffuse_color = base_color
    material.metallic = metallic
    material.roughness = roughness

    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled:
        principled.inputs["Base Color"].default_value = base_color
        principled.inputs["Metallic"].default_value = metallic
        principled.inputs["Roughness"].default_value = roughness
        if "Coat Weight" in principled.inputs:
            principled.inputs["Coat Weight"].default_value = 0.32
        if "Coat Roughness" in principled.inputs:
            principled.inputs["Coat Roughness"].default_value = 0.16
        if emission_color and "Emission Color" in principled.inputs:
            principled.inputs["Emission Color"].default_value = emission_color
        if "Emission Strength" in principled.inputs:
            principled.inputs["Emission Strength"].default_value = emission_strength
    return material


def add_and_apply_modifier(
    obj: bpy.types.Object,
    name: str,
    modifier_type: str,
    **properties,
) -> None:
    modifier = obj.modifiers.new(name=name, type=modifier_type)
    for key, value in properties.items():
        setattr(modifier, key, value)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def style_bust(bust: bpy.types.Object, porcelain: bpy.types.Material) -> None:
    bust.data.materials.clear()
    bust.data.materials.append(porcelain)

    # A medium decimation is enough for broad, intentional facets while keeping
    # the nose, ears, jaw, and clavicle legible at the application size.
    add_and_apply_modifier(bust, "Sculptural reduction", "DECIMATE", ratio=0.22)
    add_and_apply_modifier(bust, "Triangulated facets", "TRIANGULATE")
    for polygon in bust.data.polygons:
        polygon.use_smooth = False


def create_armature() -> tuple[bpy.types.Object, dict[str, bpy.types.EditBone]]:
    armature_data = bpy.data.armatures.new("AirPostureControls")
    armature = bpy.data.objects.new("AirPostureRig", armature_data)
    bpy.context.scene.collection.objects.link(armature)
    armature.show_in_front = True
    armature.data.display_type = "BBONE"
    armature["asset_role"] = "Editable posture controls"
    armature["controls"] = "CTRL_chest, CTRL_neck, CTRL_head"

    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    chest = armature_data.edit_bones.new("CTRL_chest")
    chest.head = (0.0, 0.0, -1.02)
    chest.tail = (0.0, 0.0, -0.48)

    neck = armature_data.edit_bones.new("CTRL_neck")
    neck.head = chest.tail
    neck.tail = (0.0, 0.0, -0.08)
    neck.parent = chest
    neck.use_connect = True

    head = armature_data.edit_bones.new("CTRL_head")
    head.head = neck.tail
    head.tail = (0.0, 0.0, 0.82)
    head.parent = neck
    head.use_connect = True

    bpy.ops.object.mode_set(mode="POSE")
    for bone_name in ("CTRL_chest", "CTRL_neck", "CTRL_head"):
        pose_bone = armature.pose.bones[bone_name]
        pose_bone.rotation_mode = "XYZ"
        pose_bone.custom_shape_scale_xyz = (0.8, 0.8, 0.8)
    bpy.ops.object.mode_set(mode="OBJECT")
    return armature, {"chest": chest, "neck": neck, "head": head}


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    amount = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return amount * amount * (3.0 - 2.0 * amount)


def skin_bust(obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    chest_group = obj.vertex_groups.new(name="CTRL_chest")
    neck_group = obj.vertex_groups.new(name="CTRL_neck")
    head_group = obj.vertex_groups.new(name="CTRL_head")

    for vertex in obj.data.vertices:
        z = vertex.co.z
        y = vertex.co.y

        # Keep the cranium and face effectively rigid. The earlier broad
        # vertical blend reached through the jaw and cheeks, so pitching the
        # head made the face compress. Only the lower neck now blends into the
        # chest; a front-aware jaw mask carries the chin with CTRL_head while
        # leaving the cervical column free to bend behind it.
        neck_amount = smoothstep(-0.64, -0.46, z)
        head_base = smoothstep(-0.30, -0.20, z)
        jaw_height = smoothstep(-0.42, -0.27, z)
        jaw_front = 1.0 - smoothstep(-0.34, -0.14, y)
        head_amount = max(head_base, jaw_height * jaw_front)
        chest_weight = 1.0 - neck_amount
        head_weight = head_amount
        neck_weight = max(0.0, neck_amount - head_amount)
        total = chest_weight + neck_weight + head_weight
        chest_group.add([vertex.index], chest_weight / total, "REPLACE")
        neck_group.add([vertex.index], neck_weight / total, "REPLACE")
        head_group.add([vertex.index], head_weight / total, "REPLACE")

    modifier = obj.modifiers.new(name="AirPosture rig", type="ARMATURE")
    modifier.object = armature
    obj.parent = armature


def rigid_skin_to_bone(
    obj: bpy.types.Object,
    armature: bpy.types.Object,
    bone_name: str,
) -> None:
    group = obj.vertex_groups.new(name=bone_name)
    group.add([vertex.index for vertex in obj.data.vertices], 1.0, "REPLACE")

    modifier = obj.modifiers.new(name="AirPosture rig", type="ARMATURE")
    modifier.object = armature
    obj.parent = armature


def create_plinth(graphite: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=16, location=(0, 0.03, -1.02))
    plinth = bpy.context.object
    plinth.name = "GraphitePlinth"
    plinth.scale = (0.83, 0.52, 0.095)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    plinth.data.materials.append(graphite)
    for polygon in plinth.data.polygons:
        polygon.use_smooth = True
    return plinth


def create_status_collar(status: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.235,
        minor_radius=0.020,
        major_segments=48,
        minor_segments=8,
        location=(0, 0.005, -0.36),
    )
    collar = bpy.context.object
    collar.name = "StatusCollar"
    collar.scale.y = 0.86
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    collar.data.materials.append(status)
    for polygon in collar.data.polygons:
        polygon.use_smooth = True
    return collar


def create_preview_scene() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    def point_at(obj: bpy.types.Object, point: Vector) -> None:
        obj.rotation_euler = (point - obj.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(2.75, -5.8, 1.75))
    camera = bpy.context.object
    camera.name = "PreviewCamera"
    camera.data.lens = 70
    point_at(camera, Vector((0.0, 0.0, -0.02)))
    bpy.context.scene.camera = camera

    lights: list[bpy.types.Object] = []
    for name, location, energy, color, size in (
        ("KeyLight", (-3.2, -4.0, 4.5), 460.0, (0.78, 0.88, 1.0), 3.0),
        ("FillLight", (3.6, -2.0, 1.0), 190.0, (0.70, 0.80, 1.0), 2.5),
        ("RimLight", (2.0, 2.2, 3.2), 640.0, (0.42, 0.66, 1.0), 2.0),
    ):
        data = bpy.data.lights.new(name=name, type="AREA")
        data.energy = energy
        data.color = color
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.scene.collection.objects.link(light)
        light.location = location
        point_at(light, Vector((0.0, 0.0, 0.0)))
        lights.append(light)
    return camera, lights


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "Medium High Contrast"
    scene.world.color = (0.012, 0.016, 0.024)
    bpy.ops.render.render(write_still=True)


def purge_orphans() -> None:
    for _ in range(4):
        if bpy.ops.outliner.orphans_purge(do_recursive=True) == {"CANCELLED"}:
            break


def export_runtime_asset(runtime_objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in runtime_objects:
        obj.hide_render = False
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = runtime_objects[0]

    bpy.ops.wm.usd_export(
        filepath=str(USDZ_PATH),
        selected_objects_only=True,
        export_animation=False,
        export_hair=False,
        export_uvmaps=True,
        export_mesh_colors=False,
        export_normals=True,
        export_materials=True,
        export_armatures=True,
        only_deform_bones=True,
        export_shapekeys=False,
        generate_preview_surface=True,
        generate_materialx_network=False,
        convert_orientation=True,
        export_global_forward_selection="Z",
        export_global_up_selection="Y",
        export_textures_mode="NEW",
        relative_paths=True,
        export_custom_properties=True,
        triangulate_meshes=True,
        root_prim_path="/AirPostureBust",
        convert_scene_units="METERS",
        meters_per_unit=1.0,
    )


def main() -> None:
    DESIGN_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_ASSET_DIR.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0

    bust = evaluated_copy(SOURCE_BUST, "PorcelainBust")
    eyes = [
        evaluated_copy(source_name, f"GraphiteEye{side}")
        for source_name, side in zip(SOURCE_EYES, ("Left", "Right"), strict=True)
    ]
    remove_original_library_objects({bust, *eyes})
    normalize_objects([bust, *eyes], bust)
    for eye in eyes:
        center_object_origin(eye)

    porcelain = make_material(
        "Porcelain",
        (0.25, 0.31, 0.38, 1.0),
        metallic=0.22,
        roughness=0.36,
        emission_color=(0.18, 0.55, 0.32, 1.0),
        emission_strength=0.025,
    )
    graphite = make_material(
        "Graphite",
        (0.025, 0.035, 0.055, 1.0),
        metallic=0.72,
        roughness=0.23,
    )
    status = make_material(
        "StatusGlow",
        (0.04, 0.22, 0.10, 1.0),
        metallic=0.35,
        roughness=0.20,
        emission_color=(0.16, 1.0, 0.40, 1.0),
        emission_strength=2.2,
    )

    style_bust(bust, porcelain)
    for eye in eyes:
        eye.data.materials.clear()
        eye.data.materials.append(graphite)
        for polygon in eye.data.polygons:
            polygon.use_smooth = True

    armature, _ = create_armature()
    skin_bust(bust, armature)
    for eye in eyes:
        rigid_skin_to_bone(eye, armature, "CTRL_head")

    plinth = create_plinth(graphite)
    rigid_skin_to_bone(plinth, armature, "CTRL_chest")
    collar = create_status_collar(status)
    rigid_skin_to_bone(collar, armature, "CTRL_neck")
    runtime_objects = [armature, bust, *eyes, plinth, collar]

    create_preview_scene()
    render_preview()

    # Save an editable neutral source file with lights and camera intact.
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH), compress=True)

    export_runtime_asset(runtime_objects)
    purge_orphans()

    print(f"AIRPOSTURE_BLEND={BLEND_PATH}")
    print(f"AIRPOSTURE_PREVIEW={PREVIEW_PATH}")
    print(f"AIRPOSTURE_USDZ={USDZ_PATH}")
    print(f"AIRPOSTURE_BUST_VERTICES={len(bust.data.vertices)}")
    print(f"AIRPOSTURE_BUST_TRIANGLES={len(bust.data.polygons)}")


if __name__ == "__main__":
    main()
