extends SceneTree
## Bake in-place CC0 Quaternius jogging/sprinting onto the knight rig.
## Retain source articulation and vertical motion; remove horizontal root motion.
const SOURCE := "res://assets/third_party/quaternius/UAL1_Standard.glb"
const TARGET := "res://assets/third_party/fullplate_knight/knight_complete.glb"
const MAP := {"Body":"spine_02", "Head":"Head", "UpperArm.l":"upperarm_l",
 "LowerArm.l":"lowerarm_l", "Hand.l":"hand_l", "UpperLeg.l":"thigh_l",
 "LowerLeg.l":"calf_l", "Foot.l":"foot_l", "UpperArm.r":"upperarm_r",
 "LowerArm.r":"lowerarm_r", "Hand.r":"hand_r", "UpperLeg.r":"thigh_r",
 "LowerLeg.r":"calf_r", "Foot.r":"foot_r"}
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
 source_player.play("A_TPose")
 source_player.seek(0,true)
 source.force_update_all_bone_transforms()
 var corrections: Array[Basis] = []
 for i in target.get_bone_count():
  var src := source.get_bone_global_pose(source.find_bone(MAP[target.get_bone_name(i)])).basis.orthonormalized()
  var dst := target.get_bone_global_rest(i).basis.orthonormalized()
  # Align bone length axes to source's T-pose; retain the knight's bone roll.
  var aligned := Basis(Quaternion(dst.y.normalized(),src.y.normalized()))*dst
  corrections.append(src.inverse()*aligned)
 var source_hip_height := source.get_bone_global_pose(source.find_bone("pelvis")).origin.y
 var body := target.find_bone("Body")
 var hip_height := (target.global_transform*target.get_bone_global_rest(body)).origin.y
 var scale_ratio := hip_height/source_hip_height
 target_player.play("k_idle")
 target_player.seek(0,true)
 target.force_update_all_bone_transforms()
 var idle_positions: Array[Vector3] = []
 for i in target.get_bone_count():
  idle_positions.append(target.get_bone_pose_position(i))
 target_player.stop(true)
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 for clip in {"jog":"Jog_Fwd","sprint":"Sprint"}:
  var source_clip: String = {"jog":"Jog_Fwd","sprint":"Sprint"}[clip]
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
   source_player.seek(time,true)
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
   var pelvis := source.get_bone_global_pose(source.find_bone("pelvis")).origin*scale_ratio
   var hip := idle_positions[body]
   hip.y = pelvis.y-target.global_position.y
   target.set_bone_pose_position(body,hip)
   target.force_update_all_bone_transforms()
   hip.y += maxf(0.0,0.025-ground_height())
   animation.position_track_insert_key(position_track,time,hip)
  preload("res://tools/gait_bake.gd").annotate(animation,source,source_player,source_clip,scale_ratio)
  var error := preload("res://tools/animation_asset_paths.gd").save(animation,OUTPUT+clip+".tres")
  if error != OK: push_error("Could not save "+clip); quit(1); return
  print("Baked ",clip," / duration ",length," / ",SAMPLES," poses")
 source_model.free()
 target_model.free()
 quit()
