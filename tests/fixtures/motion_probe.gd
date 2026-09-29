extends CharacterBody3D
## Minimal NPC-shaped composition: no Combatant, visuals, camera or world services.
const Motion = preload("res://features/character/motion_request.gd")
var tuning: CombatTuning = preload("res://data/combat.tres")
var resources = preload("res://features/character/character_resources.gd").new()
var motor = preload("res://features/character/character_motor.gd").new()
var movement = preload("res://features/character/movement_coordinator.gd").new()
var actions = preload("res://tests/fixtures/motion_probe_actions.gd").new()
var simulation = preload("res://features/character/character_simulation.gd").new()
var intent = preload("res://features/character/character_intent.gd").new()
var combat_enabled := true
var dead := false
signal stepped

func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	collision_layer = 2
	collision_mask = 1
	resources.configure(tuning.resources,100)
	motor.configure(self,tuning,capsule)
	actions.configure(self)
	simulation.configure(self,motor,movement,actions)

func _physics_process(delta: float) -> void:
	actions.clocks(delta)
	movement.tick(delta)
	if intent.action != &"":
		actions.request(String(intent.action))
		intent.action = &""
	actions.tick()
	var motion := Motion.new()
	motion.kind = Motion.Kind.LOCOMOTION
	motion.direction = intent.movement
	motion.top_speed = 4.0
	motion.air_steering = false
	simulation.step(motion,delta)
	stepped.emit()

func reset(at: Vector3) -> void:
	actions.cancel(&"reset")
	motor.teleport(Transform3D(Basis.IDENTITY,at))
	movement.reset()
	resources.reset()
	intent.movement = Vector3.ZERO
	intent.action = &""

func _exit_tree() -> void:
	actions.cancel(&"unload")
