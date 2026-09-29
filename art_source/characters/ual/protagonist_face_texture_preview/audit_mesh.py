import bpy,bmesh,json,hashlib,os,math
from pathlib import Path
from collections import Counter,defaultdict
from mathutils import Vector

OUT=Path(__file__).resolve().parent
body=bpy.data.objects['Mannequin']
if body.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
mesh=body.data; arm=bpy.data.objects['Armature']
mesh.calc_loop_triangles()
bm=bmesh.new();bm.from_mesh(mesh);bm.normal_update()
bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table();bm.edges.ensure_lookup_table()
pos=defaultdict(list)
for v in mesh.vertices:pos[tuple(round(x,6) for x in v.co)].append(v.index)
duplicates=[ids for ids in pos.values() if len(ids)>1]
unweighted=[v.index for v in mesh.vertices if sum(g.weight for g in v.groups)<.0001]
face_ids=[p.index for p in mesh.polygons if p.center.z>1.52 and p.center.y<0]
normals=[]
for p in mesh.polygons:
    if p.index in face_ids:
        for li in p.loop_indices:
            n=mesh.corner_normals[li].vector
            normals.append((p.index,li,round(n.dot(p.normal),5),list(n),list(p.normal)))
report={
 'source_path':bpy.data.filepath,'source_sha256':hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest(),
 'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'triangles':len(mesh.loop_triangles),
 'has_custom_normals':mesh.has_custom_normals,
 'attributes':[(a.name,a.data_type,a.domain) for a in mesh.attributes],
 'uvs':[(u.name,len(set(tuple(d.uv) for d in u.data))) for u in mesh.uv_layers],
 'coincident_vertex_groups':len(duplicates),'duplicate_vertices':sum(len(g)-1 for g in duplicates),
 'unweighted_vertices':unweighted,
 'zero_area_faces':[f.index for f in bm.faces if f.calc_area()<1e-12],
 'boundary_edges':sum(e.is_boundary for e in bm.edges),
 'nonmanifold_edges':sum(not e.is_manifold for e in bm.edges),
 'loose_vertices':sum(not v.link_edges for v in bm.verts),
 'loose_edges':sum(not e.link_faces for e in bm.edges),
 'noncontiguous_edges':sum(e.is_manifold and not e.is_contiguous for e in bm.edges),
 'face_normal_dot_min':min([n[2] for n in normals],default=0),
 'bad_head_normals':[n for n in normals if n[2]<0.0],
 'bone_count':len(arm.data.bones),'actions':len(bpy.data.actions),
 'modifiers':[(m.name,m.type) for m in body.modifiers],
}
(OUT/'input_audit.json').write_text(json.dumps(report,indent=2))
print('AUDIT',json.dumps({k:v for k,v in report.items() if k not in ['bad_head_normals','attributes']}),flush=True)

# Diagnose exact-position welding on an in-memory mesh. Do not save the source.
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001)
bm.normal_update();bm.verts.ensure_lookup_table();bm.edges.ensure_lookup_table();bm.faces.ensure_lookup_table()
edge_problems=[e for e in bm.edges if not e.is_manifold]
diagnosis={
 'vertices':len(bm.verts),'faces':len(bm.faces),
 'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),
 'boundary_edges':sum(e.is_boundary for e in bm.edges),
 'nonmanifold_edges':len(edge_problems),
 'noncontiguous_edges':sum(e.is_manifold and not e.is_contiguous for e in bm.edges),
 'edge_problem_locations':[[[round(c,6) for c in v.co] for v in e.verts] for e in edge_problems],
}
(OUT/'weld_diagnosis.json').write_text(json.dumps(diagnosis,indent=2))
print('WELD_DIAGNOSIS',json.dumps(diagnosis),flush=True)
bm.free()

if os.environ.get('RENDER_AUDIT')=='1':
    scene=bpy.context.scene
    for ob in scene.objects:ob.hide_render=ob.type=='MESH' and ob!=body
    arm.data.pose_position='REST'
    gray=bpy.data.materials.new('Audit clay');gray.use_nodes=True
    bsdf=gray.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(.38,.38,.38,1);bsdf.inputs['Roughness'].default_value=.85
    body.material_slots[0].material=gray
    for slot in body.material_slots:slot.material=gray
    scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.device='CPU';scene.cycles.use_denoising=True
    scene.render.resolution_x=768;scene.render.resolution_y=896;scene.render.resolution_percentage=100
    scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.25,.25,.25,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
    for ob in list(scene.objects):
        if ob.type in {'CAMERA','LIGHT'}:bpy.data.objects.remove(ob,do_unlink=True)
    def aim(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    camera=bpy.data.objects.new('Audit camera',bpy.data.cameras.new('Audit camera'));scene.collection.objects.link(camera);scene.camera=camera
    camera.data.type='ORTHO';camera.data.ortho_scale=.46;camera.location=(.12,-4,1.66);aim(camera,(0,0,1.66))
    for name,loc,power,size in [('Key',(-3,-4,5),180,5),('Fill',(3,-2,3),130,5),('Back',(0,4,4),180,5)]:
        light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));scene.collection.objects.link(light);light.data.energy=power;light.data.size=size;light.location=loc;aim(light,(0,0,1))
    scene.render.filepath=str(OUT/'before_face.png');bpy.ops.render.render(write_still=True)
print('AUDIT_COMPLETE',flush=True)
os._exit(0)
