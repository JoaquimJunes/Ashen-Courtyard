extends RefCounted
## Shared action/motion/contact step for controlled characters. World-agnostic.
const Motion = preload("res://features/character/motion_request.gd")
const Motor = preload("res://features/character/character_motor.gd")
const Modes = preload("res://features/character/movement_coordinator.gd")
const Lifecycle = preload("res://features/abilities/action_lifecycle.gd")
var resolver := preload("res://features/character/motion_resolver.gd").new()
var actor: CharacterBody3D
var motor: Motor
var movement: Modes
var actions: Lifecycle
var swimming: RefCounted

func configure(body: CharacterBody3D, character_motor: Motor, modes: Modes, abilities: Lifecycle) -> void:
	actor = body
	motor = character_motor
	movement = modes
	actions = abilities
	resolver.configure(body,character_motor)
	actions.finished.connect(on_action_finished)
	actions.cancelled.connect(on_action_cancelled)

func on_action_finished(_id: StringName) -> void:
	resolver.reset()

func on_action_cancelled(_id: StringName, _reason: StringName) -> void:
	resolver.reset()

func step(base: Motion, delta: float) -> void:
	var can_control: bool = actions.is_available()
	# Explicit aim facing precedes an ability's directional request (e.g. a lunge).
	# Locomotion-derived facing waits until the requested velocity is resolved.
	if movement.attachment == null and (can_control or base.face_when_committed) and base.facing != Vector3.ZERO:
		motor.face_direction(base.facing,base.turn_weight)
	actions.begin_motion_frame()
	actions.advance(delta)
	var request: Motion = actions.motion
	var owner: int = actions.serial
	var definition: Resource = actions.active_definition
	if movement.attachment != null:
		var attachment: RefCounted = movement.attachment
		var destination: Vector3 = attachment.hold_position
		var applied: Motion
		if can_control and attachment.motion != null and attachment.motion.attachment_token == attachment.token:
			applied = attachment.motion
			destination = applied.target_position
		if request.kind == Motion.Kind.CONSTRAINED and request.attachment_token == attachment.token:
			destination = request.target_position
			applied = request
		if applied != null and applied.facing != Vector3.ZERO: motor.face_direction(applied.facing)
		var constrained := motor.step_constrained(destination,delta)
		movement.refresh(actor,constrained)
		attachment.motion_applied.emit(constrained,applied)
		actions.after_motion(delta)
		actions.finish_if_idle()
		return
	var before := actor.global_position
	if base.kind == Motion.Kind.WATER:
		var water_result := motor.step_water(base,delta)
		if swimming != null: swimming.after_motion(before,water_result)
		movement.refresh(actor,water_result)
		actions.after_motion(delta)
		actions.finish_if_idle()
		return
	var velocity := resolver.resolve(base,request,can_control,owner,delta)
	motor.request_horizontal(velocity)
	if (can_control or base.face_when_committed) and base.facing == Vector3.ZERO and base.face_motion:
		motor.face_direction(velocity,base.turn_weight)
	var result := motor.step(delta,actor.tuning.gravity*resolver.gravity_scale,resolver.can_step,base.centered_gravity)
	resolver.after_move(request,owner)
	if swimming != null: swimming.after_motion(before,result)
	movement.refresh(actor,result)
	# A contact callback may replace an action. The replacement starts at time
	# zero; it must not inherit motion/playback time from its predecessor's tick.
	var same_action := owner == actions.serial and definition == actions.active_definition
	actions.after_motion(delta if same_action else 0.0)
	actions.finish_if_idle()
