extends RefCounted
## One per character: resolves horizontal policies; only the motor applies them.
const Motion = preload("res://features/character/motion_request.gd")
const Motor = preload("res://features/character/character_motor.gd")
var actor: CharacterBody3D
var motor: Motor
var retained_velocity := Vector3.ZERO
var retained_owner := -1
var has_retained := false
var last_airborne := false
var last_velocity := Vector3.ZERO
var gravity_scale := 1.0
var can_step := false

func configure(body: CharacterBody3D, character_motor: Motor) -> void:
	actor = body
	motor = character_motor
	motor.motion_reset.connect(reset)

func reset() -> void:
	retained_velocity = Vector3.ZERO
	retained_owner = -1
	has_retained = false
	last_airborne = false
	last_velocity = Vector3.ZERO
	gravity_scale = 1.0
	can_step = false

func horizontal(value: Vector3) -> Vector3:
	return Vector3(value.x,0,value.z) if value.is_finite() else Vector3.ZERO

func resolve(base: Motion, override: Motion, can_control: bool, owner: int, delta: float) -> Vector3:
	if owner != retained_owner:
		retained_velocity = Vector3.ZERO
		has_retained = false
		retained_owner = owner
	last_airborne = motor.is_airborne()
	if override.air_policy != Motion.AirPolicy.INHERIT:
		# Step-settlement grace belongs to ordinary walking steering. A committed
		# roll still uses actual support when selecting its air policy/pose clock.
		last_airborne = motor.launch_pending or not actor.is_on_floor()
	gravity_scale = 1.0
	can_step = false
	if not last_airborne:
		can_step = base.allow_step and can_control if override.kind == Motion.Kind.INHERIT else override.allow_step
	var velocity := Vector3.ZERO
	if last_airborne:
		gravity_scale = maxf(0,override.air_gravity_scale) if is_finite(override.air_gravity_scale) else 1.0
		match override.air_policy:
			Motion.AirPolicy.RETAIN_DEPARTURE:
				if not has_retained:
					retained_velocity = horizontal(actor.velocity)
					has_retained = true
				velocity = retained_velocity
			Motion.AirPolicy.DIRECTED:
				velocity = horizontal(override.air_velocity)
			_:
				if base.air_steering: motor.update_air_movement(base.direction,delta)
				velocity = motor.move_velocity
	else:
		# A completed/cancelled action yields to ground locomotion here. A committed
		# action holds on the floor, but does not implicitly stop an airborne body.
		if not can_control:
			motor.move_velocity = Vector3.ZERO
			motor.turn_braking = false
		match override.kind:
			Motion.Kind.VELOCITY:
				velocity = horizontal(override.ground_velocity)
			Motion.Kind.BRAKE:
				velocity = horizontal(actor.velocity)
			_:
				if can_control:
					if base.accelerated: motor.update_ground_movement(base.direction,base.top_speed,delta)
					else: motor.move_velocity = motor.ground_direction(base.direction)*base.top_speed
					velocity = motor.move_velocity
	if override.kind == Motion.Kind.BRAKE:
		velocity = velocity.move_toward(Vector3.ZERO,maxf(0,override.braking_rate)*delta)
		motor.move_velocity = velocity
		retained_velocity = velocity
	if override.budget != null and delta > 0:
		var requested := velocity.length()*delta
		var distance := override.budget.consume(requested,not last_airborne)
		if requested > 0: velocity *= distance/requested
	last_velocity = velocity
	return velocity

func after_move(request: Motion, owner: int) -> void:
	if actor.is_on_floor():
		retained_velocity = Vector3.ZERO
		has_retained = false
	elif request.air_policy == Motion.AirPolicy.RETAIN_DEPARTURE and (not has_retained or retained_owner != owner):
		# Capture once, after wall/edge collision has resolved. Every ability uses
		# this path; no animation timer or exhausted ground budget can zero it.
		retained_velocity = horizontal(actor.velocity)
		retained_owner = owner
		has_retained = true
