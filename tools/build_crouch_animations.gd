extends SceneTree
## Bake KayKit crouch onto the Knight, preserving limb lengths and motor ownership.
## Source upper-body motion plus leg IK compensates for very different proportions.
const IK = preload("res://features/presentation/limb_ik.gd")
const SOURCE := "res://assets/third_party/kaykit/character_animations/Animations/gltf/Rig_Medium/Rig_Medium_MovementAdvanced.glb"
const TARGET := "res://assets/third_party/fullplate_knight/knight_complete.glb"
const MAP := {"Body":"chest", "Head":"head", "UpperArm.l":"upperarm.l",
 "LowerArm.l":"lowerarm.l", "Hand.l":"hand.l", "UpperLeg.l":"upperleg.l",
 "LowerLeg.l":"lowerleg.l", "Foot.l":"foot.l", "UpperArm.r":"upperarm.r",
 "LowerArm.r":"lowerarm.r", "Hand.r":"hand.r", "UpperLeg.r":"upperleg.r",
 "LowerLeg.r":"lowerleg.r", "Foot.r":"foot.r"}
const OUTPUT := "res://assets/animations/"
const SAMPLES := 61
var target: Skeleton3D
var mesh: MeshInstance3D
var surfaces: Array = []
var bind_bones: Array[int] = []

func _initialize() -> void:
 call_deferred("run")

func ground_height() -> float:
 var transforms: Array[Transform3D] = []
 for i in mesh.skin.get_bind_count():
  transforms.append(target.global_transform*target.get_bone_global_pose(bind_bones[i])*mesh.skin.get_bind_pose(i))
 var lowest := INF
 for arrays in surfaces:
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
  var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
  for v in vertices.size():
   var point := Vector3.ZERO
   for j in 4:
    var index := v*4+j
    point += (transforms[joints[index]]*vertices[v])*weights[index]
   lowest = minf(lowest,point.y)
 return lowest

func run() -> void:
 var source_model = load(SOURCE).instantiate()
 var target_model = load(TARGET).instantiate()
 root.add_child(source_model)
 root.add_child(target_model)
 var source: Skeleton3D = source_model.find_child("Skeleton3D",true,false)
 target = target_model.find_child("Skeleton3D",true,false)
 mesh = target.find_children("*","MeshInstance3D",true,false)[0]
 for i in mesh.mesh.get_surface_count(): surfaces.append(mesh.mesh.surface_get_arrays(i))
 for i in mesh.skin.get_bind_count(): bind_bones.append(target.find_bone(mesh.skin.get_bind_name(i)))
 var source_player: AnimationPlayer = source_model.find_child("AnimationPlayer",true,false)
 var target_player: AnimationPlayer = target_model.find_child("AnimationPlayer",true,false)
 source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 target_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 source_player.play("T-Pose")
 source_player.seek(0,true)
 source.force_update_all_bone_transforms()
 var corrections: Array[Basis] = []
 for i in target.get_bone_count():
  var src := source.get_bone_global_pose(source.find_bone(MAP[target.get_bone_name(i)])).basis.orthonormalized()
  var dst := target.get_bone_global_rest(i).basis.orthonormalized()
  # Align bone length axes to source's T-pose; retain the knight's bone roll.
  var aligned := Basis(Quaternion(dst.y.normalized(),src.y.normalized()))*dst
  corrections.append(src.inverse()*aligned)
 var body := target.find_bone("Body")
 target_player.play("k_idle")
 target_player.seek(0,true)
 target.force_update_all_bone_transforms()
 var idle_positions: Array[Vector3] = []
 for i in target.get_bone_count():
  idle_positions.append(target.get_bone_pose_position(i))
 target_player.stop(true)
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 for clip in ["crouch_walk","crouch_idle"]:
  var source_clip := "Crouching"
  var length := source_player.get_animation(source_clip).length
  var animation := Animation.new()
  animation.length = length
  animation.loop_mode = Animation.LOOP_LINEAR
  for i in target.get_bone_count():
   var track := animation.add_track(Animation.TYPE_ROTATION_3D)
   animation.track_set_path(track,NodePath("Armature/Skeleton3D:"+target.get_bone_name(i)))
  var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
  animation.track_set_path(position_track,NodePath("Armature/Skeleton3D:Body"))
  for sample in SAMPLES:
   var time := float(sample)/(SAMPLES-1)*length
   source_player.play(source_clip)
   source_player.seek(time if clip == "crouch_walk" else 0.27,true)
   source.force_update_all_bone_transforms()
   var globals: Array[Basis] = []
   for i in target.get_bone_count():
    var src := source.get_bone_global_pose(source.find_bone(MAP[target.get_bone_name(i)])).basis.orthonormalized()
    var desired := (src*corrections[i]).orthonormalized()
    globals.append(desired)
    var parent := target.get_bone_parent(i)
    var local := globals[parent].inverse()*desired if parent >= 0 else desired
    var rotation := local.get_rotation_quaternion()
    target.set_bone_pose_rotation(i,rotation)
    target.set_bone_pose_position(i,idle_positions[i])
    animation.rotation_track_insert_key(i,time,rotation)
   var hip := idle_positions[body]
   # Preserve source bob, but author the Knight's pelvis height for a 1.4m capsule.
   hip.y = 0.62 + (source.get_bone_global_pose(source.find_bone("hips")).origin.y-0.28)*0.7-target.global_position.y
   target.set_bone_pose_position(body,hip)
   target.force_update_all_bone_transforms()
   for side in ["l","r"]:
    var foot := target.find_bone("Foot."+side)
    var source_foot := source.get_bone_global_pose(source.find_bone("foot."+side)).origin
    var goal := Vector3(0.14 if side == "l" else -0.14,0.085+maxf(0,source_foot.y-0.145)*0.65,source_foot.z*0.65)
    if clip == "crouch_idle": goal = Vector3(0.14 if side == "l" else -0.14,0.085,0.02)
    IK.solve(target,target.find_bone("UpperLeg."+side),target.find_bone("LowerLeg."+side),foot,goal,Vector3(0.18 if side == "l" else -0.18,0,1))
    IK.set_world_basis(target,foot,target.global_basis*target.get_bone_global_rest(foot).basis)
   target.force_update_all_bone_transforms()
   hip.y += maxf(0.0,0.025-ground_height())
   target.set_bone_pose_position(body,hip)
   # Store corrected rotations, replacing the preliminary mapped sample.
   for bone in target.get_bone_count():
    animation.rotation_track_insert_key(bone,time,target.get_bone_pose_rotation(bone))
   animation.position_track_insert_key(position_track,time,hip)
  var error := preload("res://tools/animation_asset_paths.gd").save(animation,OUTPUT+clip+".tres")
  if error != OK: push_error("Could not save "+clip); quit(1); return
  print("Baked ",clip," / duration ",length," / ",SAMPLES," poses")
 source_model.free()
 target_model.free()
 quit()
