extends RefCounted
## Samples authored/native or legacy clips; physical stance belongs to the motor.
var actor: CharacterBody3D
var from_pose: Array = []
var transition := 0.0
var clock := 0.0
var camera_weight := 0.0
var camera_from := 0.0
var gait_exit_pose: Array = []
var gait_exit_time := 0.0

func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.posture.changed.connect(on_changed)

func on_changed(_lowered: bool) -> void:
	from_pose = actor.presentation.capture_pose()
	actor.model.reset_locomotion()
	gait_exit_pose.clear()
	gait_exit_time = 0
	camera_from = camera_weight
	transition = 0

func tick(delta: float) -> void:
	transition += delta
	var weight := smoothstep(0,actor.posture.definition.blend_seconds,transition)
	camera_weight = lerpf(camera_from,1.0 if actor.posture.crouched else 0.0,weight)

func sample(delta: float) -> bool:
	if not actor.posture.crouched: return false
	var model: Node3D = actor.model
	var speed: float = Vector2(actor.get_real_velocity().x,actor.get_real_velocity().z).length()
	var moving: bool = speed > 0.08 and actor.is_on_floor() and actor.actions.is_available()
	var clip := "crouch/crouch_walk" if moving else "crouch/crouch_idle"
	var native: bool = model.animation_profile != null and model.animation_profile.is_native(clip)
	if moving:
		gait_exit_pose.clear()
		gait_exit_time = 0
	elif model.animation.assigned_animation == "crouch/crouch_walk":
		# Capture the displayed, terrain-adjusted gait before sampling idle. This
		# is a pose transition only: idle never retains foot locks or runs leg IK.
		gait_exit_pose = actor.presentation.capture_pose()
		gait_exit_time = 0
	if not native: model.reset_locomotion()
	if moving:
		var reverse := -1.0 if actor.velocity.dot(-actor.global_basis.z) < -0.1 else 1.0
		clock += delta*clampf(speed/actor.posture.definition.crouch_speed,0,1.5)*reverse
	elif native:
		clock += delta
	if native: model.skeleton.reset_bone_poses()
	model.animation.play(clip)
	model.animation.seek(fposmod(clock,model.animation.get_animation(clip).length),true)
	model.animation.advance(0)
	blend()
	if native: model.finalize_native_pose(delta,actor)
	fit_clearance()
	# Blend completed poses. Refitting an already fitted exit pose recursively
	# changes its knee plane and can flip the leg while stopping on slopes.
	blend_gait_exit(delta)
	return true

func fit_clearance() -> void:
	# Lower the pelvis, then bend both legs back onto their sampled foot contacts.
	# This adapts either rig without scaling the model or rewriting source keys.
	var model: Node3D = actor.model
	var skeleton: Skeleton3D = model.skeleton
	var ik = preload("res://features/presentation/limb_ik.gd")
	skeleton.force_update_all_bone_transforms()
	var feet: Array[Transform3D] = []
	var knees: Array[Vector3] = []
	for side in ["l","r"]:
		feet.append(skeleton.global_transform*skeleton.get_bone_global_pose(model.rig.bone(skeleton,"Foot."+side)))
		knees.append(ik.position(skeleton,model.rig.bone(skeleton,"LowerLeg."+side)))
	var fold := 0.0
	if model.rig.crouch_clearance_lean > 0:
		# The short legacy torso needs a deeper forward fold instead of dropping
		# its armored shins through the floor. Keep its head facing and feet fixed.
		var body: int = model.rig.bone(skeleton,"Body")
		var head: int = model.rig.bone(skeleton,"Head")
		var head_basis: Basis = skeleton.global_basis*skeleton.get_bone_global_pose(head).basis
		var body_basis: Basis = skeleton.global_basis*skeleton.get_bone_global_pose(body).basis
		var axis: Vector3 = (ik.position(skeleton,head)-ik.position(skeleton,body)).normalized()
		var lean: float = atan2(axis.dot(-actor.global_basis.z),axis.y)
		fold = maxf(0,model.rig.crouch_clearance_lean-lean)
		ik.set_world_basis(skeleton,body,Basis(actor.global_basis.x,-fold)*body_basis)
		ik.set_world_basis(skeleton,head,head_basis)
	var high: float = -model.dodge_skin_min_height(Vector3.DOWN)
	var lower: float = maxf(0,high-actor.posture.definition.crouch_height+0.005)
	if lower < 0.00001 and fold < 0.00001: return
	model.rig.offset_world(skeleton,model.rig.bone(skeleton,"Body"),Vector3.DOWN*lower)
	skeleton.force_update_all_bone_transforms()
	for index in 2:
		var side: String = ["l","r"][index]
		var foot: int = model.rig.bone(skeleton,"Foot."+side)
		var hip: int = model.rig.bone(skeleton,"UpperLeg."+side)
		# The authored knee supplies a stable bend plane even if a slope puts
		# a foot above the lowered hip; a fixed forward pole flips at that crossing.
		var pole: Vector3 = knees[index]-ik.position(skeleton,hip)
		# Deep flexion bends upward: a lowered hip must not send a planted
		# stance knee (or its weighted shin geometry) beneath the floor.
		pole.y = maxf(pole.y,pole.length())
		# Near a fully folded leg, the upward pole can align with the ankle
		# direction and make tiny gait changes spin the knee around that axis.
		# Open the bend plane outward continuously as reach shortens. Scale by
		# the leg, not world metres; ordinary extension keeps its authored pole.
		var lower_length := knees[index].distance_to(feet[index].origin)
		var reach := ik.position(skeleton,hip).distance_to(feet[index].origin)
		var deep_fold := 1.0-smoothstep(0.4,1.2,reach/maxf(lower_length,0.00001))
		pole += actor.global_basis.x.normalized()*(-1.0 if side == "l" else 1.0)*lower_length*0.75*deep_fold
		ik.solve(skeleton,hip,model.rig.bone(skeleton,"LowerLeg."+side),foot,feet[index].origin,pole)
		ik.set_world_basis(skeleton,foot,feet[index].basis)

func blend_gait_exit(delta: float) -> void:
	if gait_exit_pose.is_empty(): return
	gait_exit_time += maxf(0.0, delta)
	var duration: float = actor.model.locomotion.tuning.transition_seconds
	var weight := smoothstep(0, maxf(0.00001, duration), gait_exit_time)
	var skeleton: Skeleton3D = actor.model.skeleton
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,gait_exit_pose[bone][0].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		skeleton.set_bone_pose_position(bone,gait_exit_pose[bone][1].lerp(skeleton.get_bone_pose_position(bone),weight))
	if gait_exit_time >= duration: gait_exit_pose.clear()

func blend() -> void:
	if from_pose.is_empty(): return
	var weight := smoothstep(0,actor.posture.definition.blend_seconds,transition)
	var skeleton: Skeleton3D = actor.model.skeleton
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,from_pose[bone][0].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		skeleton.set_bone_pose_position(bone,from_pose[bone][1].lerp(skeleton.get_bone_pose_position(bone),weight))
	if weight >= 1: from_pose.clear()

func reset() -> void:
	from_pose.clear()
	gait_exit_pose.clear()
	gait_exit_time = 0
	transition = 0
	clock = 0
	camera_weight = 0
	camera_from = 0
