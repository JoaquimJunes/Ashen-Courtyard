extends RefCounted
## Physics owns pose clocks. Rendering may only interpolate completed local poses.
const Buffer = preload("res://features/presentation/pose_buffer.gd")
var actor: CharacterBody3D
var model: Node3D
var previous = Buffer.new()
var current = Buffer.new()
var previous_transform := Transform3D.IDENTITY
var current_transform := Transform3D.IDENTITY
var previous_actor_transform := Transform3D.IDENTITY
var current_actor_transform := Transform3D.IDENTITY
var previous_fitted := false
var current_fitted := false
var sampled_frame := -1
var pose_ticks := 0
var sample_microseconds := 0
var render_microseconds := 0
var external_microseconds := 0
var interpolate := true
var _physical := false
var _evaluated := false
var in_tick := false

func configure(character: CharacterBody3D) -> void:
	actor = character
	model = actor.model
	model.pose_driver = self
	# The owner restores simulation state before hit geometry is reseeded. Actors
	# without this driver retain CharacterHitboxes' direct teleport subscription.
	if actor.hitboxes != null and actor.motor.teleported.is_connected(actor.hitboxes.reset):
		actor.motor.teleported.disconnect(actor.hitboxes.reset)
	actor.motor.teleported.connect(on_teleported)
	reset()

func physical_owner() -> bool:
	var reactions: Variant = actor.get("reactions")
	return reactions != null and reactions.active and not reactions.getting_up

func fitted_pose() -> bool:
	var reactions: Variant = actor.get("reactions")
	var posture: Variant = actor.get("posture")
	if actor.get("crawling") != null and actor.crawling.active: return true
	return model.dodging or actor.movement.attachment != null or (posture != null and posture.crouched) or (reactions != null and reactions.active)

func begin_tick() -> void:
	in_tick = true
	_evaluated = false
	external_microseconds = 0
	# A transition captures the last simulation pose, never a render interpolation.
	if physical_owner(): return
	current.apply(model.skeleton)
	model.transform = current_transform

func end_tick() -> void:
	in_tick = false

func restore_external_handoff() -> void:
	# Damage can arrive from another actor before this actor's next tick. Its
	# render pose must not become the physical start pose or saved parent frame.
	# In-tick traversal/dive fitting has already produced the intended pose.
	if in_tick or physical_owner(): return
	current.apply(model.skeleton)
	model.transform = current_transform
	model.skeleton.force_update_all_bone_transforms()

func on_teleported() -> void:
	restore_external_handoff()
	reset()
	if actor.hitboxes != null: actor.hitboxes.reset()

func evaluate(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if _evaluated: return
	_evaluated = true
	var started := Time.get_ticks_usec()
	sampled_frame = frame
	pose_ticks += 1
	var reactions: Variant = actor.get("reactions")
	var externally_sampled: bool = reactions != null and reactions.active
	var actions: Variant = actor.get("actions")
	if actions != null and actions.get("forward_dive") != null:
		externally_sampled = externally_sampled or actions.forward_dive.active
	var swimming: Variant = actor.get("swimming")
	externally_sampled = externally_sampled or (swimming != null and swimming.active and actor.movement.attachment == null)
	if not actor.dead and not externally_sampled: model.update_pose(delta)
	var swap = previous
	previous = current
	current = swap
	previous_transform = current_transform
	previous_actor_transform = current_actor_transform
	previous_fitted = current_fitted
	current.capture(model.skeleton)
	current_transform = model.transform
	current_actor_transform = actor.global_transform
	current_fitted = fitted_pose()
	var physical := physical_owner()
	if physical != _physical:
		previous.capture(model.skeleton)
		previous_transform = current_transform
	_physical = physical
	sample_microseconds = Time.get_ticks_usec()-started+external_microseconds

func display(weight: float = -1.0) -> void:
	render_microseconds = 0
	if model == null or physical_owner() or actor.dead: return
	var started := Time.get_ticks_usec()
	# Water pose is fitted to its swept capsule; interpolation must not rotate
	# that fitted body into a ceiling rejected by the motor.
	var swimming: Variant = actor.get("swimming")
	# Constraint-fitted endpoints need not remain clear along a quaternion arc.
	# Preserve their completed pose instead of inventing another fitting pass.
	if not interpolate or previous_fitted or current_fitted or (swimming != null and swimming.active):
		current.apply(model.skeleton)
		model.transform = current_transform
		render_microseconds = Time.get_ticks_usec()-started
		return
	var alpha := clampf(Engine.get_physics_interpolation_fraction() if weight < 0 else weight,0,1)
	previous.interpolate(model.skeleton,current,alpha)
	var visual_actor := previous_actor_transform.interpolate_with(current_actor_transform,alpha)
	model.transform = actor.global_transform.affine_inverse()*visual_actor*previous_transform.interpolate_with(current_transform,alpha)
	render_microseconds = Time.get_ticks_usec()-started

func reset() -> void:
	if not is_instance_valid(model) or model.skeleton == null: return
	current.capture(model.skeleton)
	previous.capture(model.skeleton)
	current_transform = model.transform
	previous_transform = current_transform
	current_actor_transform = actor.global_transform
	previous_actor_transform = current_actor_transform
	current_fitted = fitted_pose()
	previous_fitted = current_fitted
	sampled_frame = -1
	_evaluated = false
	_physical = false

func unload() -> void:
	if is_instance_valid(actor) and actor.motor.teleported.is_connected(on_teleported): actor.motor.teleported.disconnect(on_teleported)
	if is_instance_valid(model): model.pose_driver = null
	actor = null
	model = null
