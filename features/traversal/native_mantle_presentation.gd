extends RefCounted
## Optional source-native pull-up, sampled by the existing motor phase clock.
## Root translation is consumed locally; the motor still owns all displacement.
const IK = preload("res://features/presentation/limb_ik.gd")
var actor: CharacterBody3D
var serial := -1
var entry: Array = []
var source_time := 0.0
var active := false
var entry_weight := 0.0
var exit_weight := 0.0
const ENTRY_SECONDS := 0.10
const EXIT_SECONDS := 0.12

func configure(character: CharacterBody3D) -> void:
	actor = character

func reset() -> void:
	serial = -1
	entry.clear()
	source_time = 0
	active = false
	entry_weight = 0
	exit_weight = 0

func sample(action: RefCounted, idle: Array) -> bool:
	var model: Node3D = actor.model
	var profile: Resource = model.animation_profile
	if profile == null:
		reset()
		return false
	var clip: StringName = profile.mantle_clip
	if clip == &"" or not model.animation.has_animation(clip):
		reset()
		return false
	var skeleton: Skeleton3D = model.skeleton
	if serial != actor.actions.serial:
		serial = actor.actions.serial
		entry = actor.presentation.capture_pose()
		active = true
	var definition: Resource = action.definition
	var total: float = definition.lift_seconds+definition.over_seconds+definition.stand_seconds
	var clock: float = action.elapsed
	if action.phase >= action.Phase.OVER: clock += definition.lift_seconds
	if action.phase >= action.Phase.STAND: clock += definition.over_seconds
	if action.phase >= action.Phase.SETTLE: clock = total
	var animation: Animation = model.animation.get_animation(clip)
	var source_end: float = animation.length
	if profile.mantle_source_end_seconds > 0:
		source_end = minf(source_end,profile.mantle_source_end_seconds)
	# Keep the pull-up's original playback rate. Once the selected source pose
	# is reached, blend it directly to idle rather than sampling the walking tail.
	source_time = minf(source_end,animation.length*clampf(clock/maxf(total,0.00001),0,1))
	skeleton.reset_bone_poses()
	model.animation.play(clip)
	model.animation.seek(source_time,true)
	model.animation.advance(0)
	# The root motion variant keeps the authored bone keys intact in its library.
	# Reset only skeleton roots after sampling so it cannot add a second climb to
	# the accepted collision path. Pelvis/limb articulation remains source-native.
	entry_weight = smoothstep(0,ENTRY_SECONDS,clock)
	var exit_start := minf(total-EXIT_SECONDS,total*source_end/maxf(animation.length,0.00001))
	exit_weight = smoothstep(exit_start,total,clock)
	for bone in skeleton.get_bone_count():
		var rotation := skeleton.get_bone_pose_rotation(bone)
		var position := skeleton.get_bone_pose_position(bone)
		if entry.size() == skeleton.get_bone_count():
			rotation = entry[bone][0].slerp(rotation,entry_weight)
			position = entry[bone][1].lerp(position,entry_weight)
		if idle.size() == skeleton.get_bone_count():
			rotation = rotation.slerp(idle[bone][0],exit_weight)
			position = position.lerp(idle[bone][1],exit_weight)
		if skeleton.get_bone_parent(bone) < 0: position = skeleton.get_bone_rest(bone).origin
		skeleton.set_bone_pose_rotation(bone,rotation)
		skeleton.set_bone_pose_position(bone,position)
	skeleton.force_update_all_bone_transforms()
	return true

func constrain_hand(skeleton: Skeleton3D, upper: int, lower: int, hand: int, target: Vector3, pole: Vector3, basis: Basis, weight: float, lip: Vector3, normal: Vector3) -> void:
	# Blend the contact correction, not a replacement procedural arm animation.
	# Fingers and all unconstrained bones retain the imported source pose.
	var hand_world := skeleton.global_transform*skeleton.get_bone_global_pose(hand)
	var desired := hand_world.origin.lerp(target,weight)
	var near_wall := 1-smoothstep(0.10,0.30,(desired-lip).dot(normal))
	var clearance := lip.y+lerpf(0.085,0.24,1-weight)
	desired.y += maxf(0,clearance-desired.y)*near_wall
	if weight <= 0 and desired.distance_squared_to(hand_world.origin) < 0.000001: return
	var native_pole := IK.position(skeleton,lower)-IK.position(skeleton,upper)
	IK.solve(skeleton,upper,lower,hand,desired,native_pole.lerp(pole,weight))
	IK.set_world_basis(skeleton,hand,hand_world.basis.orthonormalized().slerp(basis.orthonormalized(),weight))
	skeleton.force_update_all_bone_transforms()
