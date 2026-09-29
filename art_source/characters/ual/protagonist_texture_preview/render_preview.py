"""Save a material-only painting copy and render the existing mannequin."""
import bpy
import hashlib
import json
import os
import math
from pathlib import Path
from mathutils import Vector,Quaternion

OUT=Path(__file__).resolve().parent
scene=bpy.context.scene
body=bpy.data.objects['Mannequin']
armature=bpy.data.objects['Armature']

def signature():
    mesh=body.data
    payload={
      'vertices':[list(v.co) for v in mesh.vertices],
      'faces':[list(p.vertices) for p in mesh.polygons],
      'normals':[list(n.vector) for n in mesh.corner_normals],
      'smooth':[p.use_smooth for p in mesh.polygons],
      'uvs':{u.name:[list(d.uv) for d in u.data] for u in mesh.uv_layers},
      'weights':[[(g.group,g.weight) for g in v.groups] for v in mesh.vertices],
      'group_names':[g.name for g in body.vertex_groups],
      'bones':[(b.name,b.parent.name if b.parent else '',[list(r) for r in b.matrix_local]) for b in armature.data.bones],
      'body_transform':[list(r) for r in body.matrix_world],
      'armature_transform':[list(r) for r in armature.matrix_world],
    }
    return {k:hashlib.sha256(json.dumps(v,sort_keys=True).encode()).hexdigest() for k,v in payload.items()}

baseline=json.loads((OUT/'baseline.json').read_text())
assert signature()==baseline['signatures'],'Source no longer matches the approved baseline'
original_images=[m.node_tree.nodes.get('Paint Base Color').image for m in body.data.materials]
image=bpy.data.images.load(str(OUT/'Protagonist_BaseColor_512.png'),check_existing=False)
image.name='Protagonist_BaseColor_512'
image.colorspace_settings.name='sRGB'
image.pack()
for material in body.data.materials:
    tree=material.node_tree
    texture=tree.nodes.get('Paint Base Color')
    texture.image=image;texture.interpolation='Closest';texture.extension='EXTEND'
    tree.nodes.get('UV Map').uv_map='CharacterPaint'
    bsdf=tree.nodes.get('Principled BSDF')
    bsdf.inputs['Metallic'].default_value=0
    bsdf.inputs['Roughness'].default_value=.88
    bsdf.inputs['Specular IOR Level'].default_value=.15
    tree.nodes.active=texture
    texture.select=True
    material.diffuse_color=(.48,.28,.15,1)

assert signature()==baseline['signatures'],'Texturing altered protected mesh or rig data'
validation={'geometry_uv_weights_rig_unchanged':True,'matched_properties':list(baseline['signatures']), 'vertices':baseline['vertices'],'triangles':baseline['triangles'],'bones':baseline['bones'],'texture_size':list(image.size),'filter':'Closest','displacement':False,'game_integrated':False}
(OUT/'validation.json').write_text(json.dumps(validation,indent=2))

for ob in scene.objects:
    ob.hide_render=ob.type=='MESH' and ob!=body
armature.data.pose_position='REST'
scene.render.engine='CYCLES';scene.cycles.device='CPU'
scene.cycles.samples=8;scene.cycles.use_denoising=True
scene.render.resolution_x=768;scene.render.resolution_y=896
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=True
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.25,.25,.25,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
scene.view_settings.exposure=0;scene.view_settings.gamma=1
for ob in list(scene.objects):
    if ob.type in {'CAMERA','LIGHT'}:bpy.data.objects.remove(ob,do_unlink=True)
camera_data=bpy.data.cameras.new('PreviewCamera')
camera=bpy.data.objects.new('PreviewCamera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
camera_data.type='ORTHO'
def aim(ob,point):ob.rotation_euler=(Vector(point)-ob.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size in [('Key',(-3,-4,5),180,5),('Fill',(3,-2,3),130,5),('Back',(0,4,4),180,5)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light);light.location=loc;aim(light,(0,0,1))
camera.location=(0,-4,.95);aim(camera,(0,0,.95));camera_data.ortho_scale=2.05

if os.environ.get('SAVE_PREVIEW')=='1':
    bpy.context.view_layer.objects.active=body
    for ob in bpy.context.view_layer.objects: ob.select_set(ob==body)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='IMAGE_EDITOR': area.spaces.active.image=image
    scene.tool_settings.image_paint.mode='MATERIAL'
    scene.tool_settings.image_paint.canvas=image
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Protagonist_texture_preview.blend'))
    print('SAVED_COPY',flush=True)

# Display-only arm pose uses existing bones; saved editable copy stays in Rest.
if armature.animation_data:
    armature.animation_data.action=None
    armature.animation_data.use_nla=False
armature.data.pose_position='POSE'
for bone in armature.pose.bones:
    bone.matrix_basis.identity()
for name,angle in [('upperarm_l',55),('upperarm_r',-55)]:
    bone=armature.pose.bones[name]
    basis=bone.bone.matrix_local.to_quaternion()
    bone.rotation_mode='QUATERNION'
    bone.rotation_quaternion=basis.inverted()@Quaternion(Vector((0,1,0)),math.radians(angle))@basis
if os.environ.get('POSE_CHECK')=='1':
    for name,angle in [('lowerarm_l',75),('lowerarm_r',60),('thigh_l',-35),('thigh_r',-35),('calf_l',70),('calf_r',70)]:
        bone=armature.pose.bones[name]
        bone.rotation_mode='QUATERNION'
        bone.rotation_quaternion=Quaternion(Vector((1,0,0)),math.radians(angle))
bpy.context.view_layer.update()
if os.environ.get('INSPECT_ONLY')=='1':
    print('POSE_DIAGNOSTIC',json.dumps({n:{'rest':[list(r) for r in armature.data.bones[n].matrix_local],'pose':[list(r) for r in armature.pose.bones[n].matrix],'constraints':[(c.name,c.type) for c in armature.pose.bones[n].constraints]} for n in ['Head','neck_01','root']}),flush=True)
    os._exit(0)

views={
 'front':((0,-4,.96),(0,0,.96),2.06),
 'back':((0,4,.96),(0,0,.96),2.06),
 'side':((4,0,.96),(0,0,.96),2.06),
 'face':((.12,-4,1.66),(0,0,1.66),.46),
 'three_quarter':((2,-4,.96),(0,0,.96),2.06),
}
mode=os.environ.get('PREVIEW_MODE','textured')
if mode=='original':
    for material,original in zip(body.data.materials,original_images):
        material.node_tree.nodes.get('Paint Base Color').image=original
for name in os.environ.get('PREVIEW_VIEWS','front').split(','):
    if not name: continue
    pos,target,scale=views[name]
    camera.location=pos;aim(camera,target);camera_data.ortho_scale=scale
    prefix='inspection_bend' if os.environ.get('POSE_CHECK')=='1' else mode+'_'+name
    scene.render.filepath=str(OUT/(prefix+'.png'))
    bpy.ops.render.render(write_still=True)
assert signature()==baseline['signatures'],'Preview pose changed protected source data'
print('RENDER_COMPLETE',mode,flush=True)
os._exit(0)
