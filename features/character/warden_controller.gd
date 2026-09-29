extends "res://features/character/input_controller.gd"
const BossDefinition = preload("res://features/abilities/boss_attack_definition.gd")
## Decisions produce the same intent/actions as a player or external AI controller.
var approach_time := 0.0
var sequence := 0
var last_pattern := 0

func sample(_camera_yaw: float = 0, _camera_pitch: float = 0.0) -> Intent: return intent

func decide(actor: CharacterBody3D, delta: float) -> void:
	if manual: return
	intent.movement = Vector3.ZERO
	intent.facing = Vector3.ZERO
	intent.action = &""
	if not is_instance_valid(actor.target) or actor.target.dead: return
	var offset: Vector3 = actor.target.global_position-actor.global_position
	var distance := offset.length()
	intent.aim = Intent.Aim.new(actor.global_position+Vector3.UP*1.2,actor.target.global_position+Vector3.UP*1.3)
	if actor.actions.active_definition == null:
		approach_time += delta
		intent.facing = offset
		if distance > 3.0: intent.movement = offset.normalized()
		if distance < 3.2 or (distance > 5.0 and approach_time > 1.2):
			last_pattern = 2 if distance > 5 else sequence%2
			sequence += 1
			intent.action = [&"boss_combo",&"boss_overhead",&"boss_lunge"][last_pattern]
			approach_time = 0
	elif actor.actions.phase == actor.actions.Phase.TELEGRAPH:
		var definition: Resource = actor.actions.active_definition
		var fraction: float = definition.tracking_fraction if definition is BossDefinition else 0.65
		if actor.actions.timer < definition.windup*fraction: intent.facing = offset
