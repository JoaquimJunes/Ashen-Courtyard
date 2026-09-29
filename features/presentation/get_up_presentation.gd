extends RefCounted
## Samples authored supported poses. Never moves the character's collision body.
const Definition = preload("res://features/presentation/get_up_definition.gd")
const PoseKey = preload("res://features/presentation/get_up_keyframe.gd")
const IK = preload("res://features/presentation/limb_ik.gd")
var model: Node3D
var skeleton: Skeleton3D
var definition: Definition
var standing_pose: Array = []
var recovery_pose: Array = []
var idle_transforms: Array[Transform3D] = []
var bones: Dictionary = {}
var frame := Transform3D.IDENTITY
var variant: StringName = &"face_down"
var sampled_progress := 0.0
var contact_targets: Dictionary = {}
var contact_bases: Dictionary = {}

func configure(character: CharacterBody3D) -> void:
	model = character.model
	skeleton = model.skeleton
	bones = model.rig.indices(skeleton)

func snapshot() -> Array:
	var result: Array = []
	for index in skeleton.get_bone_count():
		result.append([skeleton.get_bone_pose_rotation(index),skeleton.get_bone_pose_position(index)])
	return result

func apply(pose: Array) -> void:
	for index in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(index,pose[index][0])
		skeleton.set_bone_pose_position(index,pose[index][1])
	skeleton.force_update_all_bone_transforms()

func begin(world_poses: Array[Transform3D], selected: StringName = &"face_down", settings: Definition = preload("res://features/presentation/knight_get_up.tres"), normal: Vector3 = Vector3.UP) -> void:
	definition = settings
	variant = selected
	model.reset_locomotion()
	model.animation.play("k_idle")
	model.animation.seek(0,true)
	model.animation.advance(0)
	skeleton.force_update_all_bone_transforms()
	standing_pose = snapshot()
	idle_transforms.clear()
	for index in skeleton.get_bone_count():
		idle_transforms.append(model.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(index))
	frame = Transform3D(Basis(Quaternion(Vector3.UP,normal))*model.global_basis,model.global_position)
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		var local := world_poses[parent].affine_inverse()*world_poses[index] if parent >= 0 else skeleton.global_transform.affine_inverse()*world_poses[index]
		skeleton.set_bone_pose_rotation(index,local.basis.orthonormalized().get_rotation_quaternion())
		skeleton.set_bone_pose_position(index,local.origin)
	recovery_pose = snapshot()
	model.animation.stop(true)
	sampled_progress = 0
	contact_targets.clear()
	contact_bases.clear()
	skeleton.force_update_all_bone_transforms()

func sample(progress: float) -> void:
	if recovery_pose.is_empty(): return
	sampled_progress = clampf(progress,0,1)
	# Preserve the physical world pose exactly at handover, including orientation.
	if sampled_progress <= 0:
		apply(recovery_pose)
		return
	apply(standing_pose)
	var keys: Array[PoseKey] = definition.face_up if variant == &"face_up" else definition.face_down
	var lower: PoseKey = keys[0]
	var upper: PoseKey = keys[-1]
	for index in range(1,keys.size()):
		if sampled_progress <= keys[index].time:
			lower = keys[index-1]
			upper = keys[index]
			break
	var weight := smoothstep(lower.time,upper.time,sampled_progress)
	var pelvis := lower.pelvis.lerp(upper.pelvis,weight)
	var tilt := Quaternion.from_euler(lower.torso_degrees*PI/180).slerp(Quaternion.from_euler(upper.torso_degrees*PI/180),weight)
	var body: int = bones["Body"]
	var body_world := Transform3D(frame.basis*Basis(tilt)*idle_transforms[body].basis,frame*pelvis)
	var body_local := preload("res://features/presentation/character_rig.gd").parent_world(skeleton,body).affine_inverse()*body_world
	skeleton.set_bone_pose_position(body,body_local.origin)
	skeleton.set_bone_pose_rotation(body,body_local.basis.orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()
	var pole := lower.knee_pole.lerp(upper.knee_pole,weight).normalized()
	var knees_out := lerpf(lower.knees_out,upper.knees_out,weight)
	contact_targets.clear()
	for side in ["l","r"]:
		var foot: Vector3 = lower.left_foot.lerp(upper.left_foot,weight) if side == "l" else lower.right_foot.lerp(upper.right_foot,weight)
		var hand: Vector3 = lower.left_hand.lerp(upper.left_hand,weight) if side == "l" else lower.right_hand.lerp(upper.right_hand,weight)
		var pitch := lerpf(lower.left_foot_pitch,upper.left_foot_pitch,weight) if side == "l" else lerpf(lower.right_foot_pitch,upper.right_foot_pitch,weight)
		pose_limb("Leg",side,frame*foot,frame.basis*Vector3(-knees_out if side == "l" else knees_out,pole.y,pole.z))
		pose_limb("Arm",side,frame*hand,frame.basis*Vector3(-1 if side == "l" else 1,0,0.5))
		var ankle: int = bones["Foot."+side]
		IK.set_world_basis(skeleton,ankle,frame.basis*Basis(Vector3.RIGHT,deg_to_rad(pitch))*idle_transforms[ankle].basis)
		contact_bases["Foot."+side] = skeleton.global_basis*skeleton.get_bone_global_pose(ankle).basis
		var wrist: int = bones["Hand."+side]
		var hand_turn := Basis(Vector3.RIGHT,PI/2*(1-smoothstep(0.26,0.6,sampled_progress))) if side == "l" else Basis(Vector3.BACK,deg_to_rad(85)*(1-smoothstep(0.65,1,sampled_progress)))
		IK.set_world_basis(skeleton,wrist,frame.basis*hand_turn*idle_transforms[wrist].basis)
		contact_bases["Hand."+side] = skeleton.global_basis*skeleton.get_bone_global_pose(wrist).basis
		contact_targets["Foot."+side] = frame*foot
		contact_targets["Hand."+side] = frame*hand
	# Keep the head following the torso, with a small anticipatory look towards upright.
	var head: int = bones["Head"]
	var head_world := skeleton.global_basis*skeleton.get_bone_global_pose(head).basis
	var head_weight := smoothstep(0.4,0.9,sampled_progress)*0.4
	IK.set_world_basis(skeleton,head,Basis(head_world.get_rotation_quaternion().slerp((frame.basis*idle_transforms[head].basis).get_rotation_quaternion(),head_weight)))
	var entry := smoothstep(0,definition.entry_fraction,sampled_progress)
	if entry < 1:
		for index in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(index,recovery_pose[index][0].slerp(skeleton.get_bone_pose_rotation(index),entry))
			skeleton.set_bone_pose_position(index,recovery_pose[index][1].lerp(skeleton.get_bone_pose_position(index),entry))
	var exit := smoothstep(definition.idle_blend_start,1,sampled_progress)
	if exit > 0:
		for index in skeleton.get_bone_count():
			skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(standing_pose[index][0],exit))
			skeleton.set_bone_pose_position(index,skeleton.get_bone_pose_position(index).lerp(standing_pose[index][1],exit))
	# Small mesh clearance correction also covers the transition from arbitrary
	# ragdoll poses; it does not translate the capsule or change gameplay height.
	var normal := frame.basis.y.normalized()
	var lift := maxf(0,definition.ground_clearance-model.dodge_skin_min_height(model.global_basis.inverse()*normal))*entry
	model.rig.offset_world(skeleton,body,normal*lift)
	skeleton.force_update_all_bone_transforms()
	# Mesh clearance must not drag a planted hand/boot upwards with the pelvis.
	if entry >= 1 and exit == 0:
		var hand_planted := sampled_progress <= definition.hand_plant_end if variant == &"face_down" else sampled_progress >= definition.back_hand_plant_start and sampled_progress <= definition.back_hand_plant_end
		if hand_planted:
			pose_limb("Arm","l",contact_targets["Hand.l"],frame.basis*Vector3(-1,0,0.5))
			IK.set_world_basis(skeleton,bones["Hand.l"],contact_bases["Hand.l"])
		if sampled_progress >= (definition.back_foot_plant_start if variant == &"face_up" else definition.front_foot_plant_start) and sampled_progress <= definition.foot_plant_end:
			pose_limb("Leg","l",contact_targets["Foot.l"],frame.basis*Vector3(-knees_out,pole.y,pole.z))
			IK.set_world_basis(skeleton,bones["Foot.l"],contact_bases["Foot.l"])

func pose_limb(kind: String, side: String, target: Vector3, pole: Vector3) -> void:
	IK.solve(skeleton,bones["Upper"+kind+"."+side],bones["Lower"+kind+"."+side],bones[("Foot." if kind == "Leg" else "Hand.")+side],target,pole)

func reset() -> void:
	standing_pose.clear()
	recovery_pose.clear()
	idle_transforms.clear()
	contact_targets.clear()
	contact_bases.clear()
	sampled_progress = 0
	variant = &"face_down"
	definition = null
