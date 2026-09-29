extends RefCounted
## Read-only diagnostics. Never advances movement or action clocks.
var actor: CharacterBody3D
var last_request := "None"
func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.actions.request_completed.connect(on_request_completed)
func reset() -> void:
	last_request = "None"
func on_request_completed(action: StringName, result: RefCounted) -> void:
	last_request = "%s: %s" % [action,String(result.reason).replace("_"," ")]
func description() -> String:
	var velocity: Vector3 = actor.motor.last_result.velocity
	var actual_speed := Vector2(velocity.x,velocity.z).length()
	var phase := "None"
	var rise := 0.0
	if actor.forward_dive.active:
		phase = ["Preparation","Airborne dive","Grounded roll"][actor.forward_dive.phase]
		rise = actor.forward_dive.launch_height
	elif actor.state == actor.State.DODGE:
		phase = "Airborne tuck" if actor.dodge_phase == actor.DodgePhase.AIRBORNE else "Grounded roll"
		rise = actor.actions.active_definition.height
	var profile := "None"
	if actor.actions.active_definition != null: profile = actor.actions.active_definition.id
	return "Ledge: %s / %s\n" % [actor.traversal.status,actor.traversal.reason]+"Mode: %s  |  Action: %s  |  Grounded: %s\nSpeed: %.2f m/s  |  Sprint: %s  |  Reversal braking: %s\nDodge: %s  |  %s\nRoll: %.2f s  |  Travel left: %.2f m  |  Selected rise: %.2f m\nVertical speed: %.2f m/s  |  Landing: %s (%.2f m equivalent, %.1f damage)\nTimed landing roll: %s  |  Invulnerable: %s  |  Last request: %s" % [actor.movement.mode,actor.State.keys()[actor.state],actor.movement.mode == &"grounded",actual_speed,actor.sprinting,actor.turn_braking,profile,phase,actor.dodge_ground_time,actor.dodge_distance_left,rise,actor.velocity.y,actor.landing.severity,actor.landing.last_height,actor.landing.last_damage,"Success" if actor.landing.roll_succeeded else "No",actor.invulnerable,last_request]
