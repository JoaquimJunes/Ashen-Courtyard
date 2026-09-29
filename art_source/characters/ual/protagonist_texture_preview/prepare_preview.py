"""Read the approved painting copy; render projection guides without editing it."""
import bpy
import hashlib
import json
import math
import os
from pathlib import Path
import numpy as np
from mathutils import Vector

OUT = Path(__file__).resolve().parent
scene = bpy.context.scene
body = bpy.data.objects['Mannequin']
armature = bpy.data.objects['Armature']

def signature():
    mesh = body.data
    payload = {
        'vertices': [list(v.co) for v in mesh.vertices],
        'faces': [list(p.vertices) for p in mesh.polygons],
        'normals': [list(n.vector) for n in mesh.corner_normals],
        'smooth': [p.use_smooth for p in mesh.polygons],
        'uvs': {u.name: [list(d.uv) for d in u.data] for u in mesh.uv_layers},
        'weights': [[(g.group, g.weight) for g in v.groups] for v in mesh.vertices],
        'group_names': [g.name for g in body.vertex_groups],
        'bones': [(b.name,b.parent.name if b.parent else '',[list(r) for r in b.matrix_local]) for b in armature.data.bones],
        'body_transform': [list(r) for r in body.matrix_world],
        'armature_transform': [list(r) for r in armature.matrix_world],
    }
    return {k: hashlib.sha256(json.dumps(v,sort_keys=True).encode()).hexdigest() for k,v in payload.items()}

baseline = signature()
(OUT/'baseline.json').write_text(json.dumps({'signatures':baseline,'vertices':len(body.data.vertices),'triangles':sum(len(p.vertices)-2 for p in body.data.polygons),'bones':len(armature.data.bones)},indent=2))
mesh=body.data
mesh.calc_loop_triangles()
np.savez_compressed(OUT/'surface_data.npz',
    positions=np.array([v.co[:] for v in mesh.vertices]),
    triangles=np.array([t.vertices[:] for t in mesh.loop_triangles]),
    triangle_uvs=np.array([[mesh.uv_layers['CharacterPaint'].data[i].uv[:] for i in t.loops] for t in mesh.loop_triangles]),
    triangle_normals=np.array([[mesh.corner_normals[i].vector[:] for i in t.loops] for t in mesh.loop_triangles]))

for ob in scene.objects:
    ob.hide_render = ob.type == 'MESH' and ob != body
armature.data.pose_position='REST'
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=8
scene.cycles.use_denoising=True
scene.render.resolution_x=1024
scene.render.resolution_y=1024
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(0.11,0.11,0.11,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=0.8
scene.view_settings.view_transform='Standard'
scene.view_settings.look='None'
scene.view_settings.exposure=0
scene.view_settings.gamma=1

for ob in list(scene.objects):
    if ob.type in {'CAMERA','LIGHT'}:
        bpy.data.objects.remove(ob,do_unlink=True)
camera_data=bpy.data.cameras.new('PreviewCamera')
camera=bpy.data.objects.new('PreviewCamera',camera_data)
scene.collection.objects.link(camera)
scene.camera=camera
camera_data.type='ORTHO'

def aim(ob,at):
    ob.rotation_euler=(Vector(at)-ob.location).to_track_quat('-Z','Y').to_euler()

for name,loc,power,size in [('Key',(-3,-4,5),220,5),('Fill',(3,-2,3),130,5),('Back',(0,4,4),220,5)]:
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK';data.size=size
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light);light.location=loc;aim(light,(0,0,1))

# The source primer is preserved in the source file. Only guide-render materials change.
for material in body.data.materials:
    material=material
    bsdf=material.node_tree.nodes.get('Principled BSDF')
    for link in list(bsdf.inputs['Base Color'].links):material.node_tree.links.remove(link)
    bsdf.inputs['Base Color'].default_value=(0.45,0.45,0.45,1)
    bsdf.inputs['Roughness'].default_value=0.85
    bsdf.inputs['Metallic'].default_value=0

views={
 'front':{'location':(0,-4,.915),'target':(0,0,.915),'scale':2.12},
 'back':{'location':(0,4,.915),'target':(0,0,.915),'scale':2.12},
 'face':{'location':(0,-4,1.67),'target':(0,0,1.67),'scale':.43},
 'head_back':{'location':(0,4,1.67),'target':(0,0,1.67),'scale':.43},
}
(OUT/'projection_cameras.json').write_text(json.dumps(views,indent=2))
for name,v in views.items():
    if name not in os.environ.get('PREVIEW_VIEWS','front,back,face,head_back').split(','):
        continue
    camera.location=v['location'];aim(camera,v['target']);camera_data.ortho_scale=v['scale']
    scene.render.filepath=str(OUT/('guide_'+name+'.png'))
    bpy.ops.render.render(write_still=True)
assert baseline==signature(),'Guide generation changed the mannequin'
print('PREPARE_COMPLETE',flush=True)
# Avoid the host audio service hanging Blender during interpreter teardown.
os._exit(0)
