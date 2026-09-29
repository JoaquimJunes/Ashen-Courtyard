"""Reopen the saved copy and independently check the actual deliverable."""
import bpy,bmesh,json,hashlib,math,os
from pathlib import Path
from collections import defaultdict,Counter
from mathutils import Quaternion,Vector
OUT=Path(__file__).resolve().parent
SOURCE=OUT.parent/'UAL_reference.blend'
report=json.loads((OUT/'repair_report.json').read_text())
def key(v):return tuple(round(float(c),7) for c in v)
def digest(data):return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
def capture():
    body=bpy.data.objects['Mannequin'];arm=bpy.data.objects['Armature']
    if body.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
    mesh=body.data
    mesh.calc_loop_triangles()
    weights=defaultdict(list)
    for v in mesh.vertices:
        values={body.vertex_groups[g.group].name:g.weight for g in v.groups if g.weight>1e-8}
        total=sum(values.values())
        weights[key(v.co)].append({name:w/total for name,w in values.items()} if total else {})
    return {
        'positions':{key(v.co) for v in mesh.vertices},
        'faces':Counter(tuple(sorted(key(mesh.vertices[i].co) for i in p.vertices)) for p in mesh.polygons),
        'triangles':Counter(tuple(sorted(key(mesh.vertices[i].co) for i in t.vertices)) for t in mesh.loop_triangles),
        'weights':weights,
        'bones':digest([(b.name,b.parent.name if b.parent else '',[list(r) for r in b.matrix_local]) for b in arm.data.bones]),
        'transforms':digest([[list(r) for r in ob.matrix_world] for ob in [body,arm]]),
        'modifiers':[(m.name,m.type,m.object.name if m.type=='ARMATURE' else '') for m in body.modifiers],
        'actions':sorted((a.name,list(a.frame_range)) for a in bpy.data.actions),
    }
assert Path(bpy.data.filepath)==SOURCE
source=capture()
bpy.ops.wm.open_mainfile(filepath=str(OUT/'UAL_face_textured_repaired.blend'))
saved=capture();body=bpy.data.objects['Mannequin'];arm=bpy.data.objects['Armature'];mesh=body.data
assert saved['positions']<=source['positions']
split_faces={tuple(sorted(key(v) for v in face)) for face in report['uv_seam_split_face_positions']}
removed_faces=source['faces']-saved['faces']
assert sum(removed_faces.values())==1+len(split_faces)
assert split_faces<=set(removed_faces)
assert not (saved['triangles']-source['triangles'])
assert sum((source['triangles']-saved['triangles']).values())==1
for prop in ['bones','transforms','modifiers','actions']:assert source[prop]==saved[prop],prop
repair_points={key(v['position']) for v in report['weight_repairs']}
preserved_weights=0
for point,variants in saved['weights'].items():
    for new in variants:
        assert abs(sum(new.values())-1)<1e-5
        if point in repair_points:continue
        assert any(set(new)==set(old) and all(abs(new[n]-old[n])<1e-5 for n in new) for old in source['weights'][point]),point
        preserved_weights+=1
bm=bmesh.new();bm.from_mesh(mesh);bm.normal_update()
checks={
    'input_file_unchanged':hashlib.sha256(SOURCE.read_bytes()).hexdigest()==report['source_sha256'],
    'saved_file_reopened':True,'surface_shape_preserved':True,'render_triangles_preserved_except_one_stray':True,
    'skeleton_transforms_modifiers_and_43_actions_preserved':True,
    'existing_weight_ratios_preserved':preserved_weights,
    'unweighted_vertices':sum(not any(g.weight>0 for g in v.groups) for v in mesh.vertices),
    'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),
    'inconsistent_winding_edges':sum(e.is_manifold and not e.is_contiguous for e in bm.edges),
    'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),
    'flat_shading_preserved':all(not p.use_smooth for p in mesh.polygons),
    'bones':len(arm.data.bones),'actions':len(bpy.data.actions),
    'armature_objects':sum(ob.type=='ARMATURE' for ob in bpy.data.objects),
}
bm.free()
uv=mesh.uv_layers['CharacterPaint']
checks['finite_uvs_in_unit_square']=all(all(math.isfinite(float(c)) and -.00001<=c<=1.00001 for c in value.uv) for value in uv.data)
mesh.calc_loop_triangles()
uv_degenerate=[]
for triangle in mesh.loop_triangles:
    a,b,c=[uv.data[i].uv for i in triangle.loops]
    area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5
    if area<1e-12:uv_degenerate.append(triangle.polygon_index)
checks['collapsed_uv_triangles']=len(uv_degenerate)
checks['collapsed_uv_polygon_indices']=sorted(set(uv_degenerate))
for material in mesh.materials:
    node=material.node_tree.nodes['Player Base Color']
    assert node.interpolation=='Closest' and list(node.image.size)==[512,512]
    assert node.image.packed_file
    assert hashlib.sha256(bytes(node.image.packed_file.data)).hexdigest()==report['texture_sha256']
checks['packed_512_texture_matches_existing_player_texture']=True
# Pose only in memory. Every repaired facial point must now follow the head.
if arm.animation_data:arm.animation_data.action=None;arm.animation_data.use_nla=False
for bone in arm.pose.bones:bone.matrix_basis.identity()
arm.data.pose_position='POSE';bpy.context.view_layer.update()
dg=bpy.context.evaluated_depsgraph_get()
evaluated=body.evaluated_get(dg);rest={v.index:v.co.copy() for v in evaluated.data.vertices}
head=arm.pose.bones['Head'];head.rotation_mode='QUATERNION';head.rotation_quaternion=Quaternion(Vector((1,0,0)),math.radians(20))
bpy.context.view_layer.update();evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get())
distances=[(evaluated.data.vertices[v.index].co-rest[v.index]).length for v in mesh.vertices if key(v.co) in repair_points]
checks['repaired_face_vertices_follow_head']=bool(distances) and min(distances)>.005
checks['minimum_repaired_face_motion_metres']=min(distances)
checks['game_integrated']=False
assert checks['input_file_unchanged'] and checks['finite_uvs_in_unit_square']
assert checks['collapsed_uv_triangles']==0
assert not checks['unweighted_vertices'] and not checks['nonmanifold_edges'] and not checks['inconsistent_winding_edges'] and not checks['zero_area_faces']
assert checks['repaired_face_vertices_follow_head']
(OUT/'validation.json').write_text(json.dumps(checks,indent=2))
print('VALIDATION_COMPLETE',json.dumps(checks),flush=True)
os._exit(0)
