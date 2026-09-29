extends RefCounted
## Reads movement/landing state. Never launches, applies damage or acquires actions.
var actor: CharacterBody3D
var phase := ""
var blend_time := 0.0
var from_pose: Array = []
var exit_pose: Array = []
var exit_time := 0.0

func configure(character: CharacterBody3D) -> void:
	actor = character

func reset() -> void:
	phase = ""
	from_pose.clear()
	exit_pose.clear()
	blend_time = 0
	exit_time = 0

func snapshot() -> Array:
	var result: Array = []
	for bone in actor.model.skeleton.get_bone_count():
		result.append([actor.model.skeleton.get_bone_pose_rotation(bone),actor.model.skeleton.get_bone_pose_position(bone)])
	return result

func blend_from(pose: Array, weight: float) -> void:
	var skeleton: Skeleton3D = actor.model.skeleton
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,pose[bone][0].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		skeleton.set_bone_pose_position(bone,pose[bone][1].lerp(skeleton.get_bone_pose_position(bone),weight))
	fit_clearance()

func fit_clearance() -> void:
	var skeleton: Skeleton3D = actor.model.skeleton
	var root: int = actor.model.rig.bone(skeleton,"Body")
	var lift: float = maxf(0,0.025-actor.model.dodge_skin_min_height())
	actor.model.rig.offset_world(skeleton,root,actor.model.global_basis*Vector3.UP*lift)

func sample(delta: float) -> bool:
	var next := ""
	var progress := 0.0
	if actor.movement.in_flight and not actor.is_on_floor() and actor.motor.step_control_left <= 0:
		if actor.movement.jump_consumed and actor.movement.airborne_time < 0.22:
			next = "jump_start"
			progress = clampf(actor.movement.airborne_time/0.22,0,1)*0.65
		else:
			next = "jump_air"
			progress = fmod(actor.movement.airborne_time/2.5,1.0)
	elif actor.landing.animation_time < actor.landing.animation_duration and actor.landing.last_height > 0.04:
		next = "jump_land"
		progress = clampf(actor.landing.animation_time/actor.landing.animation_duration,0,1)
	if next == "":
		if phase != "":
			exit_pose = snapshot()
			exit_time = 0
			phase = ""
		return false
	if next != phase:
		from_pose = snapshot()
		blend_time = 0
		phase = next
		exit_pose.clear()
	var model: Node3D = actor.model
	model.reset_locomotion()
	model.animation.play("jump/"+next)
	model.animation.seek(progress,true)
	model.animation.advance(0)
	if next == "jump_land" and actor.landing.severity == &"soft":
		var landing_pose := snapshot()
		model.animation.play("k_idle")
		model.animation.seek(0,true)
		model.animation.advance(0)
		# Soft contact uses a shallower compression and never commits gameplay.
		blend_from(landing_pose,0.55)
	blend_time += delta
	if blend_time >= 0.06: from_pose.clear()
	if not from_pose.is_empty(): blend_from(from_pose,smoothstep(0,0.06,blend_time))
	else: fit_clearance()
	return true

func blend_exit(delta: float) -> void:
	if exit_pose.is_empty(): return
	exit_time += delta
	blend_from(exit_pose,smoothstep(0,0.10,exit_time))
	if exit_time >= 0.10: exit_pose.clear()
