extends RefCounted
## Native tap-cast sequence, sampled from the accepted action's gameplay clock.
var actor: CharacterBody3D
var current: Resource
var current_profile: RefCounted
var serial := -1
var from_pose: Array = []
var upper_body: Dictionary = {}
var lower_body_weight := 1.0

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
	if context == null or context.presentation.role != &"spell": return
	if context.animations == null: return
	var profile: Resource = context.animations.profile
	current = profile.spell_cast
	if current == null: return
	current_profile = context.animations
	serial = actor.actions.serial
	from_pose = actor.presentation.capture_pose()
	lower_body_weight = 0.0 if actor.movement.in_flight and not actor.is_on_floor() else 1.0
	actor.model.reset_locomotion()

func on_finished(_id: StringName) -> void: reset()
func on_cancelled(_id: StringName, _reason: StringName) -> void: reset()

func reset() -> void:
	if current != null and is_instance_valid(actor) and is_instance_valid(actor.model): actor.model.reset_locomotion()
	current = null
	current_profile = null
	serial = -1
	from_pose.clear()

func sample(delta: float, airborne: bool = false) -> bool:
	if current == null: return false
	var action: Resource = actor.actions.active_definition
	if actor.dead or action == null or actor.actions.serial != serial:
		reset()
		return false
	var model: Node3D = actor.model
	var skeleton: Skeleton3D = model.skeleton
	var player: AnimationPlayer = model.animation
	var base: Array = actor.presentation.capture_pose()
	var selected: Dictionary = current.sample_time(actor.timer,action,current_profile)
	skeleton.reset_bone_poses()
	player.play(current_profile.resolved(selected.clip))
	player.seek(selected.time,true)
	player.advance(0)
	var enter := 1.0 if current.blend_in <= 0 else smoothstep(0,minf(current.blend_in,action.windup),actor.timer)
	var end: float = action.windup+action.recovery
	var leave := 0.0 if current.blend_out <= 0 else smoothstep(end-minf(current.blend_out,action.recovery),end,actor.timer)
	lower_body_weight = move_toward(lower_body_weight,0.0 if airborne else 1.0,maxf(delta,0)/0.08)
	for bone in skeleton.get_bone_count():
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
	model.position_cast_light(actor)
	return true

func unload() -> void:
	if is_instance_valid(actor) and actor.actions.started.is_connected(on_started):
		actor.actions.started.disconnect(on_started)
		actor.actions.finished.disconnect(on_finished)
		actor.actions.cancelled.disconnect(on_cancelled)
	reset()
	actor = null
