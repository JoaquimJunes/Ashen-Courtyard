import bpy,os,math,json
from pathlib import Path
from mathutils import Vector,Quaternion
OUT=Path(__file__).resolve().parent
scene=bpy.context.scene;body=bpy.data.objects['Mannequin'];arm=bpy.data.objects['Armature']
if body.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
mode=os.environ.get('REVIEW_MODE','textured')
requested_views=os.environ.get('REVIEW_VIEWS',os.environ.get('REVIEW_VIEW','face')).split(',')
for ob in scene.objects:ob.hide_render=ob.type=='MESH' and ob!=body
if mode=='clay':
    material=bpy.data.materials.new('Review clay');material.use_nodes=True
    shader=material.node_tree.nodes['Principled BSDF'];shader.inputs['Base Color'].default_value=(.38,.38,.38,1);shader.inputs['Roughness'].default_value=.85
    for slot in body.material_slots:slot.material=material
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.resolution_x=768;scene.render.resolution_y=896;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='Standard';scene.view_settings.look='None'
scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.25,.25,.25,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.8
for ob in list(scene.objects):
    if ob.type in {'CAMERA','LIGHT'}:bpy.data.objects.remove(ob,do_unlink=True)
def aim(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
camera=bpy.data.objects.new('Review camera',bpy.data.cameras.new('Review camera'));scene.collection.objects.link(camera);scene.camera=camera;camera.data.type='ORTHO'
for name,loc,power,size in [('Key',(-3,-4,5),180,5),('Fill',(3,-2,3),130,5),('Back',(0,4,4),180,5)]:
    ob=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'));scene.collection.objects.link(ob)
    ob.data.energy=power;ob.data.size=size;ob.location=loc;aim(ob,(0,0,1))
if arm.animation_data:arm.animation_data.action=None;arm.animation_data.use_nla=False
for bone in arm.pose.bones:bone.matrix_basis.identity()
arm.data.pose_position='POSE'
for name,angle in [('upperarm_l',55),('upperarm_r',-55)]:
    bone=arm.pose.bones[name];basis=bone.bone.matrix_local.to_quaternion()
    bone.rotation_mode='QUATERNION';bone.rotation_quaternion=basis.inverted()@Quaternion(Vector((0,1,0)),math.radians(angle))@basis
views={
 'face':((.12,-4,1.66),(0,0,1.66),.46),
 'face_side':((3,-4,1.66),(0,0,1.66),.46),
 'front':((0,-4,.96),(0,0,.96),2.06),
 'side':((4,0,.96),(0,0,.96),2.06),
 'back':((0,4,.96),(0,0,.96),2.06),
 'bend':((2,-4,.96),(0,0,.96),2.06),
}
for view in requested_views:
    if view=='bend':
        assert view==requested_views[-1],'Inspection pose must be rendered last'
        for name,angle in [('lowerarm_l',75),('lowerarm_r',60),('thigh_l',-35),('thigh_r',-35),('calf_l',70),('calf_r',70),('Head',15)]:
            bone=arm.pose.bones[name];bone.rotation_mode='QUATERNION';bone.rotation_quaternion=Quaternion(Vector((1,0,0)),math.radians(angle))
    bpy.context.view_layer.update()
    location,target,scale=views[view]
    camera.location=location;aim(camera,target);camera.data.ortho_scale=scale
    scene.render.filepath=str(OUT/(mode+'_'+view+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDER_COMPLETE',mode,view,flush=True)
os._exit(0)
