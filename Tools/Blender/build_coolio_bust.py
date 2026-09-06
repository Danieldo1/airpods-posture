"""Create the lightweight AirPosture derivative of the user-supplied Coolio file.

Blender --background --disable-autoexec 'Coolio 2.0 UPDATED.blend' \
  --python Tools/Blender/build_coolio_bust.py

Only geometry is read from the source. Embedded scripts, drivers, and its full
production rig are not required by the exported model. Original file is untouched.
"""
from pathlib import Path
import json
import math
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / 'DesignAssets'
RUNTIME = ROOT / 'Sources/AirPostureMac/Resources/AirPostureBust.usdz'
HIP_Z = 1.03
HEAD_Z = 1.76
HEAD_SCALE = 1.12
TOP_Z = HEAD_Z + (2.411562 - HEAD_Z) * HEAD_SCALE
SCALE = 2.0 / (TOP_Z - HIP_Z)
MID_Z = (TOP_Z + HIP_Z) / 2


def smooth(a, b, v):
    t = max(0.0, min(1.0, (v-a)/(b-a)))
    return t*t*(3-2*t)


def stylize(p):
    # Keep the entire jaw/face rigidly proportioned, blending only at the neck.
    amount = smooth(1.70, 1.83, p.z)
    scale = 1 + (HEAD_SCALE - 1) * amount
    return Vector((p.x*scale, p.y*scale, HEAD_Z+(p.z-HEAD_Z)*scale))


def normalized(p):
    return Vector((p.x*SCALE, p.y*SCALE, (p.z-MID_Z)*SCALE))


def source_copy(name, output):
    source = bpy.data.objects[name]
    vertices = [source.matrix_world @ v.co for v in source.data.vertices]
    mesh = bpy.data.meshes.new(output)
    mirrored = source.matrix_world.determinant() < 0
    faces = [tuple(reversed(p.vertices)) if mirrored else tuple(p.vertices) for p in source.data.polygons]
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for original, copied in zip(source.data.polygons, mesh.polygons):
        copied.material_index = original.material_index
    obj = bpy.data.objects.new(output, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def activate(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def crop(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for origin, normal in [((0,0,HIP_Z),(0,0,1))]:
        geom = list(bm.verts)+list(bm.edges)+list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geom, dist=0.00001, plane_co=origin, plane_no=normal, clear_inner=True)
        edges = [e for e in bm.edges if e.is_boundary]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    activate(obj)
    sub = obj.modifiers.new('Soft silhouette', 'SUBSURF')
    sub.levels = 1
    bpy.ops.object.modifier_apply(modifier=sub.name)


def material(name, color, roughness=.65):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = (*color,1)
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color,1)
    p.inputs['Roughness'].default_value = roughness
    return m


def facial_curve(name, points, radius, mat):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.resolution_u = 3
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    curve.use_fill_caps = True
    spline = curve.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for p, co in zip(spline.bezier_points, points):
        p.co = co
        p.handle_left_type = p.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(obj)
    activate(obj)
    bpy.ops.object.convert(target='MESH')
    obj.data.materials.append(mat)
    return obj


def surface_front(body, x, z):
    hit, location, _, _ = body.ray_cast(Vector((x,-2,z)),Vector((0,1,0)))
    if not hit: raise ValueError(f'No face surface at {x}, {z}')
    return location.y


def brow(name, side, black, body):
    # Seat the entire brow arc against the curved forehead, including its outer
    # end. Flat depth coordinates visibly float away at the 45-degree yaw limit.
    points = []
    for i in range(5):
        t = i / 4
        x = side * (.094 + .123*t)
        z = 2.25 + .018*math.sin(math.pi*t)
        points.append((x, surface_front(body,x,z)-.007, z))
    return facial_curve(name,points,.010,black)


def mouth_line(body, mat):
    points=[]
    for x in [-.09,-.045,0,.045,.09]:
        z=1.984 + .002*(x/.09)**2
        points.append((x,surface_front(body,x,2.003)-.008,z))
    return facial_curve('MouthLine',points,.005,mat)


# Preserve the original arms/hands and bake a relaxed pose into the export.
# Coordinates are the supplied Coolio rest pose (metres), before normalization.
SOURCE_SHOULDER = Vector((.2672,.0205,1.6451))
SOURCE_ELBOW = Vector((.6122,.0275,1.619))
SOURCE_WRIST = Vector((.9135,.0059,1.594))
RELAXED_SHOULDER = SOURCE_SHOULDER.copy()
RELAXED_ELBOW = Vector((.46,0,1.38))
RELAXED_WRIST = Vector((.42,-.17,1.18))
UPPER_ROTATION = (SOURCE_ELBOW-SOURCE_SHOULDER).rotation_difference(RELAXED_ELBOW-RELAXED_SHOULDER)
FOREARM_ROTATION = (SOURCE_WRIST-SOURCE_ELBOW).rotation_difference(RELAXED_WRIST-RELAXED_ELBOW)
UPPER_SCALE = (RELAXED_ELBOW-RELAXED_SHOULDER).length/(SOURCE_ELBOW-SOURCE_SHOULDER).length
FOREARM_SCALE = (RELAXED_WRIST-RELAXED_ELBOW).length/(SOURCE_WRIST-SOURCE_ELBOW).length


def arm_weights(p):
    arm = smooth(.235,.36,abs(p.x))*smooth(1.38,1.50,p.z)*(1-smooth(1.76,1.82,p.z))
    elbow = smooth(.55,.67,abs(p.x))
    wrist = smooth(.865,.955,abs(p.x))
    return arm*(1-elbow), arm*elbow*(1-wrist), arm*wrist


def relaxed_position(p):
    upper, forearm, hand = arm_weights(p)
    side = 1 if p.x >= 0 else -1
    q = Vector((abs(p.x),p.y,p.z))
    upper_point = RELAXED_SHOULDER + UPPER_ROTATION @ ((q-SOURCE_SHOULDER)*UPPER_SCALE)
    forearm_point = RELAXED_ELBOW + FOREARM_ROTATION @ ((q-SOURCE_ELBOW)*FOREARM_SCALE)
    # Modestly smaller hands keep every finger visible above the hip crop;
    # fingers retain their original topology and travel with a wrist joint.
    hand_point = RELAXED_WRIST + FOREARM_ROTATION @ ((q-SOURCE_WRIST)*.60)
    result = q*(1-upper-forearm-hand)+upper_point*upper+forearm_point*forearm+hand_point*hand
    result.x *= side
    return result


def rig_create():
    data=bpy.data.armatures.new('CoolioPostureControls')
    obj=bpy.data.objects.new('AirPostureRig',data)
    bpy.context.scene.collection.objects.link(obj)
    activate(obj)
    bpy.ops.object.mode_set(mode='EDIT')
    joints=[
        ('CTRL_root',None,(0,0,HIP_Z)),
        ('CTRL_chest','CTRL_root',(0,0,1.16)),
        ('CTRL_neck','CTRL_chest',(0,0,1.65)),
        ('CTRL_head','CTRL_neck',(0,0,1.80)),
        ('CTRL_shoulderLeft','CTRL_chest',RELAXED_SHOULDER),
        ('CTRL_shoulderRight','CTRL_chest',(-RELAXED_SHOULDER.x,RELAXED_SHOULDER.y,RELAXED_SHOULDER.z)),
        ('CTRL_elbowLeft','CTRL_shoulderLeft',RELAXED_ELBOW),
        ('CTRL_elbowRight','CTRL_shoulderRight',(-RELAXED_ELBOW.x,RELAXED_ELBOW.y,RELAXED_ELBOW.z)),
        ('CTRL_wristLeft','CTRL_elbowLeft',RELAXED_WRIST),
        ('CTRL_wristRight','CTRL_elbowRight',(-RELAXED_WRIST.x,RELAXED_WRIST.y,RELAXED_WRIST.z)),
        ('CTRL_eyeLeft','CTRL_head',(.155,-.295,2.162)),
        ('CTRL_eyeRight','CTRL_head',(-.155,-.295,2.162)),
        ('CTRL_browLeft','CTRL_head',(.155,-.308,2.26)),
        ('CTRL_browRight','CTRL_head',(-.155,-.308,2.26)),
        ('CTRL_mouthLeft','CTRL_head',(.086,-.332,1.981)),
        ('CTRL_mouthRight','CTRL_head',(-.086,-.332,1.981)),
    ]
    for name,parent,location in joints:
        bone=data.edit_bones.new(name)
        bone.head=normalized(stylize(Vector(location)))
        bone.tail=bone.head+Vector((0,0,.1))
        if parent: bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    obj.show_in_front=True
    obj['source_model']='User-supplied Coolio 2.0 UPDATED.blend'
    obj['posture_controls']='Root, Chest, Neck, Head, LeftShoulder, RightShoulder'
    obj['coordinate_contract']='Blender -Y forward, +Z up; runtime +Z forward, +Y up'
    return obj


def skin(obj,rig,rigid=None):
    groups={b.name:obj.vertex_groups.new(name=b.name) for b in rig.data.bones}
    for v in obj.data.vertices:
        p=v.co.copy()
        if rigid:
            weights={rigid:1.0}
        else:
            upper, forearm, hand = arm_weights(p)
            torso = max(0,1-upper-forearm-hand)
            root=1-smooth(HIP_Z+.02,1.30,p.z)
            head=smooth(1.73,1.84,p.z)
            neck=smooth(1.58,1.74,p.z)*(1-head)
            chest=max(0,1-root-head-neck)
            corner=math.exp(-((abs(p.x)-.086)/.062)**2-((p.z-1.984)/.043)**2)
            corner*=1-smooth(-.29,-.21,p.y)
            corner*=head*.9
            side='Left' if p.x>=0 else 'Right'
            weights={'CTRL_root':root*torso,'CTRL_chest':chest*torso,'CTRL_neck':neck*torso,
                     'CTRL_head':(head-corner)*torso,'CTRL_mouth'+side:corner*torso,
                     'CTRL_shoulder'+side:upper,'CTRL_elbow'+side:forearm,'CTRL_wrist'+side:hand}
        total=sum(weights.values())
        for name,weight in weights.items():
            if weight>0.00001: groups[name].add([v.index],weight/total,'REPLACE')
        v.co=normalized(stylize(p if rigid else relaxed_position(p)))
    for p in obj.data.polygons: p.use_smooth=True
    mod=obj.modifiers.new('Posture deformation','ARMATURE')
    mod.object=rig
    obj.parent=rig


def preview():
    scene=bpy.context.scene
    scene.world=bpy.data.worlds.new('PreviewWorld')
    scene.world.color=(.16,.16,.16)
    bpy.ops.object.camera_add(location=(.7,-6,.55))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO'
    camera.data.ortho_scale=2.7
    scene.camera=camera
    for location,energy,size in [((-3,-4,5),450,4),((3,-2,1),220,3),((2,3,4),400,3)]:
        bpy.ops.object.light_add(type='AREA',location=location)
        light=bpy.context.object
        light.data.energy=energy
        light.data.shape='DISK'
        light.data.size=size
        light.rotation_euler=(-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='BLENDER_EEVEE'
    scene.render.resolution_x=600
    scene.render.resolution_y=600
    scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.render.image_settings.file_format='PNG'
    scene.render.image_settings.color_mode='RGBA'
    scene.render.filepath=str(DESIGN/'CoolioBust-preview.png')
    bpy.ops.render.render(write_still=True)


def main():
    body=source_copy('coolio_mesh.001','CoolioBody')
    eyes=[source_copy('eye.L.005','BlackEyeLeft'),source_copy('eye.R.005','BlackEyeRight')]
    teeth=[source_copy('teeth_top.005','TeethTop'),source_copy('teeth_bottom.005','TeethBottom')]
    for obj in list(bpy.data.objects):
        if obj not in [body,*eyes,*teeth]: bpy.data.objects.remove(obj,do_unlink=True)
    for text in list(bpy.data.texts): bpy.data.texts.remove(text)
    crop(body)
    clay=material('CoolioClay',(.64,.39,.27))
    black=material('FeatureBlack',(.008,.010,.013),.4)
    mouth=material('MouthDark',(.075,.025,.019))
    ivory=material('TeethIvory',(.90,.84,.71))
    body.data.materials.clear()
    body.data.materials.append(clay)
    body.data.materials.append(mouth)
    for e in eyes: e.data.materials.clear(); e.data.materials.append(black)
    for t in teeth: t.data.materials.clear(); t.data.materials.append(ivory)
    brows=[brow('BlackBrowLeft',1,black,body),brow('BlackBrowRight',-1,black,body)]
    lips=mouth_line(body,mouth)
    rig=rig_create()
    skin(body,rig)
    skin(lips,rig)
    for e,side in zip(eyes,['Left','Right']): skin(e,rig,'CTRL_eye'+side)
    for b,side in zip(brows,['Left','Right']): skin(b,rig,'CTRL_brow'+side)
    for t in teeth: skin(t,rig,'CTRL_head')
    runtime=[rig,body,lips,*eyes,*teeth,*brows]
    preview()
    activate(rig)
    bpy.context.preferences.filepaths.save_version=0
    for _ in range(3): bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(DESIGN/'CoolioBust.blend'),compress=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in runtime: obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    bpy.ops.wm.usd_export(filepath=str(RUNTIME),selected_objects_only=True,export_animation=False,
        export_hair=False,export_uvmaps=False,export_mesh_colors=False,export_normals=True,
        export_materials=True,export_armatures=True,only_deform_bones=True,export_shapekeys=False,
        generate_preview_surface=True,generate_materialx_network=False,convert_orientation=True,
        export_global_forward_selection='NEGATIVE_Z',export_global_up_selection='Y',
        export_textures_mode='NEW',relative_paths=True,export_custom_properties=True,
        triangulate_meshes=True,root_prim_path='/AirPostureBust',convert_scene_units='METERS',meters_per_unit=1)
    meshes=[o for o in runtime if o.type=='MESH']
    report={'source':'Coolio 2.0 UPDATED.blend','height':2,'bones':len(rig.data.bones),
            'vertices':sum(len(o.data.vertices) for o in meshes),
            'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes),
            'meshes':[o.name for o in meshes],'usdzBytes':RUNTIME.stat().st_size}
    (DESIGN/'CoolioBust-metrics.json').write_text(json.dumps(report,indent=2)+'\n')
    print('COOLIO_EXPORT',report)

if __name__=='__main__': main()
