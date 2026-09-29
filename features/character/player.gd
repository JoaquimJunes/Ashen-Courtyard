extends Combatant
const RegenPolicy = preload("res://features/character/resource_regeneration_policy.gd")

@export var combat_enabled := true
@export var body_definition: BodyDefinition = preload("res://features/character/data/knight_body.tres")
@export var model_scene: PackedScene = preload("res://scenes/models/ual_player.tscn")
const ItemLoadout = preload("res://features/items/item_loadout_definition.gd")
@export var starter_loadout: ItemLoadout = preload("res://features/items/data/starter_loadout.tres")
var visuals = preload("res://features/presentation/knight_visuals.gd").new()
var model: Node3D
var sword: Node3D
var forward_dive: RefCounted:
	get: return actions.forward_dive
	set(value): actions.forward_dive = value

signal simulation_stepped(delta: float)
var actions = preload("res://features/abilities/ability_controller.gd").new()
var items = preload("res://features/items/character_items.gd").new()
var posture = preload("res://features/character/character_posture.gd").new()
var crawling = preload("res://features/crawling/crawling.gd").new()
var movement = preload("res://features/character/movement_coordinator.gd").new()
var landing = preload("res://features/character/landing_response.gd").new()
var presentation = preload("res://features/presentation/character_presentation.gd").new()
var pose_driver = preload("res://features/presentation/character_pose_driver.gd").new()
var reactions: Node
var traversal = preload("res://features/traversal/ledge_traversal.gd").new()
var swimming = preload("res://features/swimming/swimming.gd").new()
const Motion = preload("res://features/character/motion_request.gd")
var simulation = preload("res://features/character/character_simulation.gd").new()

signal resources_changed(stamina: float, mana: float, flasks: int, spell: int)
const State = preload("res://features/character/character_states.gd").Action
const DodgePhase = preload("res://features/character/character_states.gd").DodgePhase
var dodge_phase: int:
	get: return actions.dodge_phase
	set(value): actions.dodge_phase = value
var dodge_ground_time: float:
	get: return actions.dodge_ground_time
	set(value): actions.dodge_ground_time = value
var dodge_distance_left: float:
	get: return actions.dodge_distance_left
	set(value): actions.dodge_distance_left = value
var state: int:
	get: return actions.state
	set(value): actions.state = value
var stamina: float:
	get: return resources.stamina
	set(value): resources.stamina = value
var mana: float:
	get: return resources.mana
	set(value): resources.mana = value
var flasks: int:
	get: return resources.flasks
	set(value): resources.flasks = value
var selected_spell: int:
	get: return items.equipment.selected_spell
	set(value): items.equipment.select(&"spell",value)
var cast_spell: int:
	get: return actions.cast_spell
	set(value): actions.cast_spell = value
var timer: float:
	get: return actions.timer
	set(value): actions.timer = value
var stamina_wait: float:
	get: return resources.stamina_wait
	set(value): resources.stamina_wait = value
var mana_wait: float:
	get: return resources.mana_wait
	set(value): resources.mana_wait = value
var buffered: String:
	get: return actions.buffered
	set(value): actions.buffered = value
var buffer_time: float:
	get: return actions.buffer_time
	set(value): actions.buffer_time = value
var combo: int:
	get: return actions.combo
	set(value): actions.combo = value
var combo_until: float:
	get: return actions.combo_until
	set(value): actions.combo_until = value
var serial: int:
	get: return actions.serial
	set(value): actions.serial = value
var released: bool:
	get: return actions.released
	set(value): actions.released = value
var dodge_dir: Vector3:
	get: return actions.dodge_dir
	set(value): actions.dodge_dir = value
var move_velocity: Vector3:
	get: return motor.move_velocity
	set(value): motor.move_velocity = value
var turn_braking: bool:
	get: return motor.turn_braking
	set(value): motor.turn_braking = value
var controller = preload("res://features/character/input_controller.gd").new()
var targeting = preload("res://features/combat/character_targeting.gd").new()
var target: Combatant:
	get: return targeting.target
	set(value): targeting.target = value
var locked: bool:
	get: return targeting.locked
	set(value): targeting.locked = value
var yaw := 0.0
var pitch := -0.24
var sprinting := false
var aiming = preload("res://features/combat/player_aim.gd").new()
var rig: Node3D
var arm: SpringArm3D
var casting_light: MeshInstance3D
var camera: Camera3D

func _ready() -> void:
	if services == null: services = get_tree().root.get_node("GameSession").combat_context_for(self)
	setup(tuning.player_health,body_definition)
	visuals.configure(self,model_scene,tuning.presentation)
	model = visuals.model
	sword = visuals.sword
	movement.coyote_seconds = tuning.movement.coyote_seconds
	actions.configure(self)
	if not items.configure(self): push_error("Item setup: "+items.last_error)
	simulation.configure(self,motor,movement,actions)
	landing.configure(self,tuning.landing)
	posture.configure(self)
	crawling.configure(self)
	presentation.configure(self)
	traversal.configure(self)
	swimming.configure(self)
	simulation.swimming = swimming
	targeting.configure(self)
	casting_light = Shapes.orb(model,0.18,Vector3(-0.42,1.32,-0.52),Color("72dfe5"))
	casting_light.visible = false
	reactions = preload("res://features/reactions/reaction_controller.gd").new()
	add_child(reactions)
	reactions.configure(self)
	hitboxes = preload("res://features/combat/character_hitboxes.gd").new()
	if not hitboxes.configure(self,model): push_error("Player requires a valid fitted hitbox profile")
	rig = Node3D.new()
	rig.set_script(preload("res://features/presentation/shoulder_camera.gd"))
	rig.subject = self
	add_child(rig)
	arm = rig.arm
	camera = rig.camera
	var swim_ui := preload("res://features/swimming/swim_hud.gd").new()
	swim_ui.name = "SwimmingHUD"
	swim_ui.actor = self
	add_child(swim_ui)
	damage_applied.connect(_on_damaged)
	died.connect(_on_died)
	pose_driver.configure(self)

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or dead or controller.manual: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_look(event.relative)
	if swimming.active or crawling.active: return # Stance/depth controls are sampled in physics.
	if combat_enabled and event.is_action_pressed("lock"):
		targeting.toggle()
	if combat_enabled and event.is_action_pressed("spell_one"): selected_spell = 0
	if combat_enabled and event.is_action_pressed("spell_two"): selected_spell = 1
	if event.is_action_pressed("light") and not event.is_echo():
		if combat_enabled: controller.attack_press()
	if event.is_action_released("light"):
		var attack: String = controller.attack_release()
		if attack != "": request_input_action(attack)
	for action in ["heavy", "dodge", "jump", "cast", "heal"]:
		if event.is_action_pressed(action) and not event.is_echo():
			if controller.attack_holding: actions.release_heavy_charge()
			controller.reset_attack()
			request_input_action(action)

func request_input_action(action: String) -> void:
	if action == "heavy_charge":
		actions.request_heavy_charge()
		return
	if action == "cancel_heavy_charge":
		actions.release_heavy_charge()
		return
	if action == "crouch" and swimming.try_crouch_entry(): return
	actions.request(action,true)

func apply_mouse_look(relative: Vector2) -> void:
	if locked: return
	yaw -= relative.x * 0.003 * float(CameraPreferences.values.sensitivity)
	var vertical := -1.0 if CameraPreferences.values.invert_y else 1.0
	pitch = clampf(pitch - relative.y * 0.0025 * float(CameraPreferences.values.sensitivity) * vertical, -1.35 if swimming.active else -1.05, 1.35 if swimming.active else 0.65)

func movement_direction() -> Vector3:
	return motor.ground_direction(controller.sample(rig.rotation.y).movement)

func camera_anchor(height: float) -> Vector3:
	return presentation.camera_anchor(height)

func spend_stamina(amount: float) -> bool:
	return resources.try_spend(amount)

func begin(action: String) -> bool:
	# Compatibility queue helper. A true return means queued, not paid/started.
	var result := actions.request(action)
	return not result.resolved

func clear_dodge() -> void:
	actions.clear_dodge()

func _physics_process(delta: float) -> void:
	pose_driver.begin_tick()
	# Resolve releases swallowed by a menu before clocks can open the strike.
	if not controller.manual and controller.attack_holding and not Input.is_action_pressed("light"):
		request_input_action(controller.tick_attack(0))
	swimming.prepare(delta)
	presentation.crouch.tick(delta)
	if reactions.active:
		reactions.tick(delta)
		resources.tick(delta,false)
		resources_changed.emit(stamina,mana,flasks,selected_spell)
		finish_sensing(delta)
		return
	tick_damage_history(delta)
	visuals.tick(delta,dead)
	actions.clocks(delta)
	movement.tick(delta)
	landing.tick(delta)
	targeting.tick(delta)
	if dead:
		motor.stop()
		finish_sensing(delta)
		return
	resources.tick(delta,RegenPolicy.stamina_allowed(self,movement,actions.is_available()))
	var intent = controller.sample(rig.rotation.y,rig.rotation.x)
	if swimming.active or movement.attachment != null:
		controller.reset_stance()
	else:
		var stance: String = controller.tick_stance(intent.crouch_held,delta,posture.crouched or crawling.active,crawling.definition.hold_seconds)
		if stance != "": request_input_action(stance)
	swimming.sample_intent(intent)
	traversal.intent_tick(intent,delta)
	# Ongoing exertion is processed before new committed requests.
	var direction: Vector3 = motor.ground_direction(intent.movement)
	var wants_sprint: bool = not crawling.active and state == State.FREE and movement.mode == &"grounded" and not motor.is_airborne() and intent.sprint and direction != Vector3.ZERO
	if wants_sprint and posture.crouched: wants_sprint = posture.stand()
	if intent.action != &"":
		if controller.attack_holding: actions.release_heavy_charge()
		controller.reset_attack()
		request_input_action(String(intent.action))
		intent.action = &""
	if not controller.manual and combat_enabled and not swimming.active and not crawling.active:
		var attack: String = controller.tick_attack(delta)
		if attack != "": request_input_action(attack)
	var exertion: float = swimming.definition.fast_cost*delta if swimming.wants_fast else (tuning.sprint_cost_per_second*delta if wants_sprint else 0.0)
	var ongoing_paid: bool = actions.tick(exertion)
	sprinting = wants_sprint and ongoing_paid and state == State.FREE
	invulnerable = false
	presentation.prepare()
	var motion := Motion.new()
	motion.kind = Motion.Kind.LOCOMOTION
	motion.direction = direction
	motion.top_speed = posture.definition.crouch_speed if posture.crouched else (tuning.sprint_speed if sprinting else tuning.move_speed)
	motion.allow_step = true
	motion.facing = intent.facing
	motion.face_motion = true
	if locked and is_instance_valid(target) and not target.dead:
		# Running intent overrides lock-facing even when stamina limits speed.
		if intent.sprint and direction != Vector3.ZERO and not posture.crouched:
			motion.facing = Vector3.ZERO
		else:
			var offset := target.global_position-global_position
			motion.facing = Vector3(offset.x,0,offset.z)
			motion.face_motion = false
	motion.turn_weight = 1.0-exp(-tuning.move_turn_response*delta)
	if crawling.active:
		motion.top_speed = crawling.definition.speed
		if presentation.crawl.blend_time < crawling.definition.blend_seconds: motion.direction = Vector3.ZERO
		motion.facing = -Basis(Vector3.UP,rig.rotation.y).z
		motion.face_motion = false
		motion.air_steering = false
	if swimming.active and movement.attachment == null:
		motion = swimming.motion(delta,ongoing_paid)
		# Face the requested horizontal direction; pitch belongs to the swim pose.
		var facing := Vector3(swimming.heading.x,0,swimming.heading.z)
		motor.face_direction(facing,1.0-exp(-tuning.move_turn_response*delta))
		motion.water_transform = presentation.swim.prepare(delta)
	simulation.step(motion,delta)
	resources_changed.emit(stamina,mana,flasks,selected_spell)
	finish_sensing(delta)

func finish_sensing(delta: float) -> void:
	# Water fits its accepted motor frame first. Other controlled poses advance
	# once here; physical reactions already published their own completed pose.
	if swimming.active and not dead and movement.attachment == null and not reactions.active:
		if presentation.swim.sampled_frame != Engine.get_physics_frames():
			motor.set_water_transform(presentation.swim.prepare(delta),swimming.definition.collider_height,delta)
		presentation.swim.accept()
	pose_driver.evaluate(delta)
	hitboxes.capture()
	swimming.tick_breath(delta)
	pose_driver.end_tick()
	simulation_stepped.emit(delta)

func _on_damaged(request: RefCounted = null) -> void:
	controller.reset_attack()
	if dead: return
	# Physical recovery retains its action slot while remaining damageable.
	# ReactionController handles lethal hits; ordinary hurt must not steal it.
	if reactions.active: return
	# LandingResponse owns impact recovery (or its timed roll). Health/death and
	# ragdoll still use the shared damage path; ordinary hurt must not replace it.
	if request != null and request.damage_type in [&"fall",&"drowning"]: return
	if actions.active_definition != null and not actions.active_definition.interrupt_on_damage: return
	actions.interrupt_for_damage()
	if combat_enabled: services.effect(global_position+Vector3.UP,Color("e87963"),0.5)

func _on_died() -> void:
	controller.reset_attack()
	traversal.release(&"death")
	actions.die()
	model.reset_locomotion()
	locked = false

func take_damage(amount: float, strike_id: String) -> bool:
	if not combat_enabled: return false
	return super.take_damage(amount,strike_id)

func reset_for_lab(at: Transform3D) -> void:
	controller.reset_attack()
	# A local reset keeps the existing camera settings and signal connections.
	# Finish action callbacks before clearing any physical reaction they triggered.
	actions.reset()
	reactions.reset()
	traversal.reset()
	swimming.reset()
	presentation.swim.reset()
	presentation.mantle.reset()
	motor.teleport(at)
	movement.reset()
	landing.reset()
	presentation.jump.reset()
	presentation.sword_attack.reset()
	presentation.spell.reset()
	posture.reset()
	crawling.reset()
	presentation.crawl.reset()
	# Posture emits changed even when standing; clear the transition it captures
	# only afterward, so reset cannot blend a previous dive/ragdoll back in.
	presentation.crouch.reset()
	reset_resources()
	items.reset_starter()
	presentation.equipment_bridge.reset()
	sprinting = false
	selected_spell = 0
	visuals.reset()
	target = null
	locked = false
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	model.dodging = false
	model.dodge_progress = 0.0
	model.casting = false
	sword.rotation = Vector3.ZERO
	casting_light.hide()
	model.reset_locomotion()
	model.animation.stop()
	model.base_clip = ""
	model.base_clock = 0.0
	model.clear_action_exit()
	model.skeleton.reset_bone_poses()
	model.update_pose(0.0)
	pose_driver.reset()
	hitboxes.reset()
	yaw = at.basis.get_euler().y
	pitch = -0.24
	camera.quaternion = Quaternion.IDENTITY
	rig.reset_follow()
	reset_physics_interpolation()
	resources_changed.emit(stamina,mana,flasks,selected_spell)

func update_ground_movement(direction: Vector3, top_speed: float, delta: float) -> void:
	motor.update_ground_movement(direction,top_speed,delta)

func try_step_up(motion: Vector3) -> bool:
	motor.allow_step = state == State.FREE
	return motor.try_step_up(motion)

func _exit_tree() -> void:
	pose_driver.unload()
	controller.reset_attack()
	swimming.reset()
	crawling.reset()
	presentation.crawl.reset()
	presentation.swim.reset()
	presentation.sword_attack.unload()
	presentation.spell.unload()
	presentation.equipment_bridge.unload()
	traversal.reset()
	presentation.mantle.reset()
	if is_instance_valid(reactions): reactions.reset()
	actions.unload()
	targeting.target = null
	targeting.locked = false
	if hitboxes != null: hitboxes.unload()

func receive_damage(request: Damage) -> bool:
	if not combat_enabled and request.damage_type not in [&"fall",&"drowning"]: return false
	return super.receive_damage(request)

func submit_intent(intent: RefCounted) -> void:
	controller.submit(intent)

func request_action(action: StringName) -> RefCounted:
	return actions.request(String(action))

func get_aim() -> Aim:
	if controller.manual and controller.intent.aim != null: return controller.intent.aim
	return aiming.sample(self,camera,target if locked and is_instance_valid(target) and not target.dead else null)
