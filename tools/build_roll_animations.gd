extends SceneTree
## Bake the CC0 Quaternius Roll onto the knight's 14-bone skeleton.
## Side/back clips keep local limb articulation but redirect torso rotation.
const SOURCE := "res://assets/third_party/quaternius/UAL1_Standard.glb"
const TARGET := "res://assets/third_party/fullplate_knight/knight_complete.glb"
const MAP := {"Body":"spine_02", "Head":"Head", "UpperArm.l":"upperarm_l",
 "LowerArm.l":"lowerarm_l", "Hand.l":"hand_l", "UpperLeg.l":"thigh_l",
 "LowerLeg.l":"calf_l", "Foot.l":"foot_l", "UpperArm.r":"upperarm_r",
 "LowerArm.r":"lowerarm_r", "Hand.r":"hand_r", "UpperLeg.r":"thigh_r",
 "LowerLeg.r":"calf_r", "Foot.r":"foot_r"}
const OUTPUT := "res://assets/animations/"
const SAMPLES := 121
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
 var idle_rotations: Array[Quaternion] = []
 var idle_positions: Array[Vector3] = []
 for i in target.get_bone_count():
  idle_rotations.append(target.get_bone_pose_rotation(i))
  idle_positions.append(target.get_bone_pose_position(i))
 target_player.stop(true)
 var body_reference: Basis = target.get_bone_global_rest(body).basis.orthonormalized()
 var length := source_player.get_animation("Roll").length
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 for clip in {"roll_forward":0.0,"roll_left":PI/2,"roll_right":-PI/2,"roll_back":PI}:
  var direction: float = {"roll_forward":0.0,"roll_left":PI/2,"roll_right":-PI/2,"roll_back":PI}[clip]
  var redirect := Basis(Vector3.UP,direction)
  var animation := Animation.new()
  animation.length = 1.0
  for i in target.get_bone_count():
   var track := animation.add_track(Animation.TYPE_ROTATION_3D)
   animation.track_set_path(track,NodePath("Armature/Skeleton3D:"+target.get_bone_name(i)))
  var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
  animation.track_set_path(position_track,NodePath("Armature/Skeleton3D:Body"))
  for sample in SAMPLES:
   var phase := float(sample)/(SAMPLES-1)
   source_player.play("Roll")
   source_player.seek(phase*length,true)
   source.force_update_all_bone_transforms()
   var globals: Array[Basis] = []
   var local_rotations: Array[Quaternion] = []
   for i in target.get_bone_count():
    var src := source.get_bone_global_pose(source.find_bone(MAP[target.get_bone_name(i)])).basis.orthonormalized()
    var desired := (src*corrections[i]).orthonormalized()
    globals.append(desired)
    var parent := target.get_bone_parent(i)
    var local := globals[parent].inverse()*desired if parent >= 0 else desired
    local_rotations.append(local.get_rotation_quaternion())
   # Redirect only the overall torso roll; knees/elbows keep their joint axes.
   var torso := Basis(local_rotations[body])
   local_rotations[body] = (redirect*(torso*body_reference.inverse())*redirect.inverse()*body_reference).get_rotation_quaternion()
   var blend := smoothstep(0.0,0.10,phase)*(1.0-smoothstep(0.82,1.0,phase))
   for i in target.get_bone_count():
    var rotation := idle_rotations[i].slerp(local_rotations[i],blend)
    target.set_bone_pose_rotation(i,rotation)
    target.set_bone_pose_position(i,idle_positions[i])
    animation.rotation_track_insert_key(i,phase,rotation)
   var pelvis := source.get_bone_global_pose(source.find_bone("pelvis")).origin*scale_ratio
   var local_hip := redirect*Vector3(pelvis.x,0,pelvis.z)
   local_hip.y = pelvis.y-target.global_position.y
   local_hip = idle_positions[body].lerp(local_hip,blend)
   target.set_bone_pose_position(body,local_hip)
   target.force_update_all_bone_transforms()
   # The short, rigid torso differs from the source; ground the actual skinned mesh.
   local_hip.y += maxf(0.0,0.025-ground_height())
   target.set_bone_pose_position(body,local_hip)
   animation.position_track_insert_key(position_track,phase,local_hip)
  var error := preload("res://tools/animation_asset_paths.gd").save(animation,OUTPUT+clip+".tres")
  if error != OK: push_error("Could not save "+clip); quit(1); return
  print("Baked ",clip," with ",SAMPLES," grounded poses")
 source_model.free()
 target_model.free()
 quit()
