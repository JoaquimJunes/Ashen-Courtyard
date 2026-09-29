extends RefCounted
## Grounded directional roll. Requests motion; only the character motor moves it.
const DodgePhase = preload("res://features/character/character_states.gd").DodgePhase
var active := false
var actor: CharacterBody3D
var definition: Resource
var travel_time := 0.0
var air_speed: float:
	# Read-only compatibility view for diagnostics. The shared resolver owns it.
	get: return actor.simulation.resolver.retained_velocity.length() if is_instance_valid(actor) else 0.0

func begin(character: CharacterBody3D) -> void:
	actor = character
	definition = actor.actions.active_definition
	travel_time = 0.0
	active = true
	actor.actions.dodge_phase = DodgePhase.GROUND_ROLL
	actor.presentation.begin_ground_roll(actor.global_basis.inverse()*actor.dodge_dir,definition.pose_blend)
	actor.model.dodge_progress = definition.animation_start

func before_move(delta: float) -> void:
	actor.invulnerable = actor.timer >= definition.immunity_start and actor.timer < definition.immunity_end
	var duration: float = maxf(0.0001,definition.ground_duration)
	var from := clampf(travel_time/duration,0,1)
	# This is a ground braking clock. Air movement is a shared motion policy.
	if actor.actions.dodge_phase != DodgePhase.AIRBORNE: travel_time += delta
	var to := clampf(travel_time/duration,0,1)
	# Integrate the easing curve so different physics rates cover the same reach.
	var area := braking_integral(1.0)
	var speed: float = minf(definition.speed,definition.distance/(duration*area))
	var distance := speed*duration*(braking_integral(to)-braking_integral(from))
	actor.actions.request_motion(actor.dodge_dir*distance/maxf(delta,0.0001),Vector3.ZERO,true,1.0,actor.actions.travel)

func braking_integral(progress: float) -> float:
	var brake: float = clampf(definition.brake_start,0,0.9999)
	if progress <= brake: return progress
	var width := 1.0-brake
	var u := (progress-brake)/width
	return brake+width*(u-u*u*u+0.5*u*u*u*u)

func after_move(delta: float) -> void:
	var grounded := actor.is_on_floor() and actor.velocity.y <= 0
	actor.actions.dodge_phase = DodgePhase.GROUND_ROLL if grounded else DodgePhase.AIRBORNE
	actor.model.set_dodge_airborne(not grounded)
	if grounded:
		actor.dodge_ground_time = minf(definition.ground_duration,actor.dodge_ground_time+delta)
	actor.model.dodge_progress = lerpf(definition.animation_start,1.0,actor.dodge_ground_time/definition.ground_duration)
	if actor.dodge_ground_time >= definition.ground_duration-0.000001:
		actor.actions.state = actor.State.FREE
		actor.actions.clear_dodge()

func finish() -> void:
	active = false
	travel_time = 0.0
	actor = null
	definition = null
