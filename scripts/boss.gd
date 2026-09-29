extends Combatant
const RegenPolicy = preload("res://features/character/resource_regeneration_policy.gd")
const BossDefinition = preload("res://features/abilities/boss_attack_definition.gd")
## Scene composition and tick ordering; decisions/actions/presentation have separate owners.
const State = preload("res://features/abilities/warden_actions.gd").Phase
@export var combat_enabled := true
@export var body_definition: BodyDefinition = preload("res://features/character/data/warden_body.tres")
@export var model_scene: PackedScene = preload("res://scenes/models/psx_warden.tscn")
var visuals = preload("res://features/presentation/knight_visuals.gd").new()
var model: Node3D
var sword: Node3D
var actions = preload("res://features/abilities/warden_actions.gd").new()
var movement = preload("res://features/character/movement_coordinator.gd").new()
var controller = preload("res://features/character/warden_controller.gd").new()
var presentation = preload("res://features/presentation/warden_presentation.gd").new()
var pose_driver = preload("res://features/presentation/character_pose_driver.gd").new()
var target: Combatant
var state: int:
	get: return actions.phase
var timer: float:
	get: return actions.timer
var pattern: int:
	get: return actions.active_definition.pattern if actions.active_definition is BossDefinition else controller.last_pattern
var serial: int:
	get: return actions.serial
var marker: MeshInstance3D:
	get: return presentation.marker
var frozen := false:
	set(value):
		frozen = value
		if value and actions.actor != null:
			actions.cancel(&"frozen")
			motor.stop()
var sprinting := false
const Motion = preload("res://features/character/motion_request.gd")
var simulation = preload("res://features/character/character_simulation.gd").new()

func _ready() -> void:
	if services == null: services = get_tree().root.get_node("GameSession").combat_context_for(self)
	setup(tuning.boss_health,body_definition)
	visuals.configure(self,model_scene,tuning.presentation)
	model = visuals.model
	sword = visuals.sword
	actions.configure(self)
	simulation.configure(self,motor,movement,actions)
	presentation.configure(self)
	died.connect(func(): actions.cancel(&"death"))
	damaged.connect(on_damaged)
	pose_driver.configure(self)

func on_damaged() -> void:
	if actions.active_definition != null and actions.active_definition.interrupt_on_damage:
		actions.cancel(&"damage")
	services.effect(global_position+Vector3.UP*1.5,Color("e7b77f"),0.4)

func submit_intent(intent: RefCounted) -> void: controller.submit(intent)
func request_action(action: StringName) -> RefCounted: return actions.request(String(action))
func get_aim() -> Aim:
	return controller.intent.aim if controller.intent.aim != null else super.get_aim()

func _physics_process(delta: float) -> void:
	pose_driver.begin_tick()
	tick_damage_history(delta)
	visuals.tick(delta,dead)
	if dead or frozen:
		actions.cancel(&"inactive")
		motor.stop()
		pose_driver.evaluate(delta)
		pose_driver.end_tick()
		return
	if not controller.manual and (not is_instance_valid(target) or target.dead):
		# No target means idle intent. Collision/gravity must continue, including
		# momentum inherited from a cancelled attack while falling.
		actions.cancel(&"target_lost")
	actions.clocks(delta)
	movement.tick(delta)
	resources.tick(delta,RegenPolicy.stamina_allowed(self,movement,actions.is_available()))
	controller.decide(self,delta)
	var intent = controller.sample()
	if intent.action != &"":
		actions.request(String(intent.action),true)
		intent.action = &""
	var approaching: bool = actions.is_available()
	actions.tick()
	presentation.prepare()
	var motion := Motion.new()
	motion.kind = Motion.Kind.LOCOMOTION
	motion.direction = intent.movement
	motion.top_speed = tuning.boss_move_speed
	motion.accelerated = false
	motion.air_steering = false
	motion.centered_gravity = false
	motion.facing = intent.facing
	motion.face_when_committed = true
	motion.turn_weight = minf(1,delta*(5 if approaching else 4))
	simulation.step(motion,delta)
	pose_driver.evaluate(delta)
	pose_driver.end_tick()

func _exit_tree() -> void:
	pose_driver.unload()
	actions.unload()
