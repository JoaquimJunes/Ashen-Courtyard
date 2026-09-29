extends RefCounted
## Samples immutable UAL clips from the committed action's clock, never a render clock.
var actor: CharacterBody3D
var current: Resource
var binding: RefCounted
var serial := -1
var from_pose: Array = []
var upper_body: Dictionary = {}
var lower_body_weight := 1.0
var return_pose: Array = []
var return_clock := 0.0
const RETURN_SECONDS := 0.15

func configure(character: CharacterBody3D) -> void:
	actor = character
	if actor.model.animation_profile == null: return
	var skeleton: Skeleton3D = actor.model.skeleton
	var upper: int = actor.model.rig.bone(skeleton,"UpperBody")
	if upper >= 0:
		for bone in skeleton.get_bone_count():
			var parent := bone
			while parent >= 0:
				if parent == upper:
					upper_body[bone] = true
					break
				parent = skeleton.get_bone_parent(parent)
	actor.actions.started.connect(on_started)
	actor.actions.finished.connect(on_finished)
	actor.actions.cancelled.connect(on_cancelled)

func on_started(_id: StringName) -> void:
	reset()
	var context: RefCounted = actor.actions.active_item
	if context == null or context.animations == null: return
	binding = context.animations
	var profile: Resource = binding.profile
	var role: StringName = context.presentation.role
	if role == &"melee_light" and not profile.light_attacks.is_empty():
		current = profile.light_attacks[posmod(actor.combo,profile.light_attacks.size())]
	elif role == &"melee_heavy": current = profile.heavy_attack
	if current == null: return
	serial = actor.actions.serial
	from_pose = actor.presentation.capture_pose()
	lower_body_weight = 0.0 if actor.movement.in_flight and not actor.is_on_floor() else 1.0
	actor.model.reset_locomotion()

func on_finished(_id: StringName) -> void: reset()
func on_cancelled(_id: StringName, reason: StringName) -> void:
	var returning := reason in [&"heavy_charge_damage",&"heavy_charge_released"]
	# Releases and damage can arrive between actor ticks, after rendering has
	# interpolated the skeleton. Recovery must capture the completed physics pose.
	if returning: actor.pose_driver.restore_external_handoff()
	var pose: Array = actor.presentation.capture_pose() if returning else []
	reset()
	return_pose = pose

func reset() -> void:
	if current != null and is_instance_valid(actor) and is_instance_valid(actor.model): actor.model.reset_locomotion()
	current = null
	binding = null
	serial = -1
	from_pose.clear()
	return_pose.clear()
	return_clock = 0.0

func sample_return(delta: float) -> bool:
	if return_pose.is_empty(): return false
	if actor.dead or not actor.actions.is_available():
		return_pose.clear()
		return false
	# Locomotion has already sampled the current combat stance beneath this blend.
	var weight := smoothstep(0,RETURN_SECONDS,return_clock)
	var skeleton: Skeleton3D = actor.model.skeleton
	for bone in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(bone,return_pose[bone][0].slerp(skeleton.get_bone_pose_rotation(bone),weight))
		skeleton.set_bone_pose_position(bone,return_pose[bone][1].lerp(skeleton.get_bone_pose_position(bone),weight))
	skeleton.force_update_all_bone_transforms()
	return_clock += maxf(delta,0)
	if weight >= 1.0: return_pose.clear()
	return true

func sample(delta: float, airborne: bool = false) -> bool:
	if current == null: return sample_return(delta)
	var action: Resource = actor.actions.active_definition
	if actor.dead or action == null or actor.actions.serial != serial:
		reset()
		return false
	var model: Node3D = actor.model
	var skeleton: Skeleton3D = model.skeleton
	var player: AnimationPlayer = model.animation
	var base: Array = actor.presentation.capture_pose()
	var recovery_length: float = binding.clip_for(current.recovery_clip).length if current.recovery_clip != &"" else 0.0
	var selected: Dictionary = current.sample_time(actor.timer,action,binding.clip_for(current.clip).length,recovery_length)
	skeleton.reset_bone_poses()
	player.play(binding.resolved(selected.clip))
	player.seek(selected.time,true)
	player.advance(0)
	var enter := 1.0 if current.blend_in <= 0 else smoothstep(0,minf(current.blend_in,action.windup),actor.timer)
	var end: float = action.windup+action.active_seconds+action.recovery
	var leave := 0.0 if current.blend_out <= 0 else smoothstep(end-minf(current.blend_out,action.recovery),end,actor.timer)
	lower_body_weight = move_toward(lower_body_weight,0.0 if airborne else 1.0,maxf(delta,0)/0.08)
	for bone in skeleton.get_bone_count():
		# Keep the flight/landing lower-body pose while the upper body swings.
		var rotation := skeleton.get_bone_pose_rotation(bone).slerp(base[bone][0],leave)
		var position := skeleton.get_bone_pose_position(bone).lerp(base[bone][1],leave)
		if from_pose.size() == skeleton.get_bone_count() and enter < 1:
			rotation = from_pose[bone][0].slerp(rotation,enter)
			position = from_pose[bone][1].lerp(position,enter)
		if not upper_body.has(bone):
			rotation = base[bone][0].slerp(rotation,lower_body_weight)
			position = base[bone][1].lerp(position,lower_body_weight)
		skeleton.set_bone_pose_rotation(bone,rotation)
		skeleton.set_bone_pose_position(bone,position)
	skeleton.force_update_all_bone_transforms()
	return true

func unload() -> void:
	if is_instance_valid(actor):
		if actor.actions.started.is_connected(on_started):
			actor.actions.started.disconnect(on_started)
			actor.actions.finished.disconnect(on_finished)
			actor.actions.cancelled.disconnect(on_cancelled)
	reset()
	actor = null
