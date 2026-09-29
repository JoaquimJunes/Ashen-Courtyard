extends "res://features/abilities/action_lifecycle.gd"
## A test-only action without knight states, animations, or dodge-specific code.
var definition: Definition
var direction := Vector3.RIGHT
var speed := 4.0
var air_speed := 7.0
var distance := 1.0
var request_until := INF
var brake := false
var contact_delta := -1.0

func definition_for(action: String) -> Definition:
	return definition if action == "probe" else null

func start_action(_action: String) -> void:
	travel.reset(distance)

func advance(_delta: float) -> void:
	if active_definition == null: return
	if timer >= definition.active_seconds:
		finish()
		return
	if timer >= request_until: return
	request_motion(direction*speed,direction*air_speed,false,1.0,travel)
	if brake:
		motion.kind = Motion.Kind.BRAKE
		motion.braking_rate = 8.0

func after_motion(delta: float) -> void:
	contact_delta = delta
