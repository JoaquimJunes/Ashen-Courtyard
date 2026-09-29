extends SceneTree
## Behavioral acceptance for Section 2 boundaries, using real scene-tree ticks.
const Intent = preload("res://features/character/character_intent.gd")
const Aim = preload("res://features/combat/aim_request.gd")
const Driver = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var stage: Node3D
var player: CharacterBody3D
var enemy: CharacterBody3D
var context: Node
var resource_events := 0
var actor_events := 0
var deaths := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame
func fresh(at: Vector3 = Vector3.ZERO) -> void:
	context.clear()
	player.controller.submit(Intent.new())
	player.reset_for_lab(Transform3D(Basis.IDENTITY,at+Vector3.UP*0.02))
	player.set_physics_process(true)
	await tick(6)
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	Shapes.solid(stage,Vector3(60,0.2,60),Vector3(0,-0.1,0),Color.GRAY)
	context = root.get_node("GameSession").configure_world(stage)
	GameInput.configure()
	Input.action_release("sprint")
	player = load("res://scenes/player.tscn").instantiate()
	player.tuning = player.tuning.duplicate(true)
	player.services = context
	player.controller.manual = true
	stage.add_child(player)
	await fresh()
	player.controller.intent.movement = Vector3.RIGHT
	player.controller.intent.sprint = true
	await tick(45)
	player.model.update_pose(1.0/60)
	check(player.sprinting and absf(player.velocity.x-player.tuning.sprint_speed) < 0.01 and player.model.animation.current_animation == "running/sprint","Scripted sprint drives physical speed and sprint animation without keyboard state")
	player.stamina = 0
	player.stamina_wait = 1
	await tick()
	player.model.update_pose(1.0/60)
	check(not player.sprinting and player.model.animation.current_animation == "running/jog","Unfunded sprint cannot claim the sprint animation")
	for route in ["direct","intent","keyboard"]:
		await fresh()
		player.stamina = player.tuning.heavy_cost
		player.stamina_wait = 1
		player.controller.intent.movement = Vector3.RIGHT
		player.controller.intent.sprint = true
		var result: RefCounted
		if route == "direct": result = player.request_action(&"heavy")
		elif route == "intent": player.controller.intent.action = &"heavy"
		else:
			player.controller.manual = false
			Input.action_press("right")
			Input.action_press("sprint")
			var event := InputEventAction.new()
			event.action = "heavy"
			event.pressed = true
			player._unhandled_input(event)
		check(player.stamina == player.tuning.heavy_cost and player.actions.active_definition == null,route+": submission does not spend or acquire ownership")
		await tick()
		check(player.state == player.State.FREE and player.stamina < player.tuning.heavy_cost and player.stamina > 35,route+": ongoing sprint cost precedes attack reservation")
		if result != null: check(result.resolved and not result.accepted and result.reason == &"insufficient_resources","Direct request reports its actual post-cost rejection")
		Input.action_release("right")
		Input.action_release("sprint")
	await fresh()
	var old: RefCounted = player.request_action(&"heavy")
	var latest: RefCounted = player.request_action(&"light")
	check(old.resolved and old.reason == &"superseded" and not latest.resolved,"One pending slot resolves superseded requests")
	await tick()
	check(latest.resolved and latest.accepted and player.state == player.State.LIGHT and player.stamina == 80,"Latest request starts and pays exactly once")
	var expired: RefCounted = player.actions.request("heavy",true)
	await tick(16)
	check(expired.resolved and expired.reason == &"expired" and player.stamina == 80,"Buffered request expires during commitment without spending again")
	await tick(40)
	check(player.actions.active_definition == null and player.actions.pending_result == null,"Expired buffer cannot start after recovery")
	await fresh()
	var paused_request: RefCounted = player.request_action(&"heavy")
	paused = true
	await tick(3)
	check(not paused_request.resolved and player.stamina == 100,"Paused request cannot start or spend")
	paused = false
	await tick()
	check(paused_request.accepted and player.stamina == 64,"Resume resolves the pending request once")
	await fresh()
	var reset_request: RefCounted = player.request_action(&"heavy")
	player.reset_for_lab(Transform3D.IDENTITY)
	check(reset_request.resolved and reset_request.reason == &"reset" and player.actions.pending_result == null,"Reset releases queued result ownership")
	await tick(2)
	check(player.actions.active_definition == null and player.stamina == 100,"Reset cannot cause a delayed start")
	# Capture the definition rather than looking up a possibly replaced equipment slot.
	await fresh()
	player.selected_spell = 1
	player.tuning.burst.recovery = 1.2
	await Driver.start(player,&"cast")
	var captured: Resource = player.actions.active_definition
	player.tuning.burst = player.tuning.burst.duplicate(true)
	player.tuning.burst.recovery = 0.1
	await tick(80)
	check(player.state == player.State.CAST and player.actions.active_definition == captured,"Burst respects its captured 1.2-second recovery instead of bolt or replacement definition")
	await tick(45)
	check(player.state == player.State.FREE and player.actions.active_definition == null,"Captured burst completes after its own windup plus recovery")
	# Mode changes are driven by a real fall from a platform.
	Shapes.solid(stage,Vector3(3,3,2),Vector3(-10,1.5,0),Color.GRAY)
	player.tuning.heavy.allowed_modes.assign([&"grounded"])
	player.tuning.heavy.windup = 0.05
	player.tuning.heavy.active_seconds = 0.8
	player.tuning.heavy.recovery = 1.0
	for policy in [0,1]:
		await fresh(Vector3(-10,3,-0.6))
		player.tuning.heavy.mode_exit_policy = policy
		await Driver.start(player,&"heavy")
		for i in 120:
			await tick()
			if player.movement.mode == &"airborne": break
		check(player.movement.mode == &"airborne","Mode policy %s sees an actual ledge departure" % policy)
		if policy == 0:
			check(player.state == player.State.FREE and player.actions.active_definition == null and player.actions.strike == null,"Default incompatible-mode policy cancels action and damage ownership")
		else:
			check(player.state == player.State.HEAVY and player.actions.active_definition != null,"An explicit continue policy can preserve a committed action on mode exit")
	# Resource owner and facade publish the same health change exactly once.
	await fresh()
	player.resources.health_changed.connect(func(_value: float,_max: float): resource_events += 1)
	player.health_changed.connect(func(_value: float,_max: float): actor_events += 1)
	player.died.connect(func(): deaths += 1)
	player.take_damage(10,"owned_health")
	check(player.health == 90 and resource_events == 1 and actor_events == 1,"Damage is published once by resources and once by its character facade")
	player.resources.heal(5)
	check(player.health == 95 and resource_events == 2 and actor_events == 2,"Healing uses the same resource notification route")
	player.reset_for_lab(Transform3D.IDENTITY)
	check(player.health == 100 and resource_events == 3 and actor_events == 3,"Reset emits one consistent resource/character health update")
	var death_request: RefCounted = player.request_action(&"light")
	player.take_damage(1000,"death")
	check(deaths == 1 and player.health == 0 and death_request.resolved and not death_request.accepted and player.actions.active_definition == null,"Death clears pending requests and health stays nonnegative")
	# Real Warden has no camera, yet shares the same lifecycle and spell services.
	await fresh()
	enemy = load("res://scenes/boss.tscn").instantiate()
	enemy.tuning = enemy.tuning.duplicate(true)
	enemy.services = context
	enemy.controller.manual = true
	enemy.position = Vector3(0,0.02,4)
	stage.add_child(enemy)
	enemy.target = player
	var intent := Intent.new()
	intent.aim = Aim.new(Vector3(0,1.2,4),Vector3(0,1.3,0))
	enemy.submit_intent(intent)
	await tick(6)
	check(enemy.find_children("*","Camera3D",true,false).is_empty(),"AI caster does not require a player camera")
	var cast: RefCounted = enemy.request_action(&"bolt")
	check(not cast.resolved and enemy.resources.mana == 100,"AI action submits through the same pending-result contract")
	await tick()
	check(cast.accepted and enemy.resources.mana == 76 and enemy.actions.active_definition.id == &"bolt","Shared lifecycle charges the AI spell exactly once")
	await tick(50)
	check(player.health == 68 and enemy.actions.active_definition == null,"AI bolt uses explicit world aim and shared damage, then releases action ownership (health=%s, action=%s, time=%s)" % [player.health,enemy.actions.active_definition,enemy.actions.timer])
	await fresh()
	enemy.resources.reset()
	await Driver.start(enemy,&"bolt")
	enemy.take_damage(1,"cancel_ai_spell")
	await tick(40)
	check(player.health == 100 and context.transients.is_empty() and enemy.actions.active_definition == null,"AI cast interruption cannot release a free or delayed projectile")
	enemy.tuning.bolt.required_capabilities.assign([&"magic_unlock"])
	check(enemy.request_action(&"bolt").reason == &"missing_capability","AI actions use the same capability requirements")
	enemy.tuning.bolt.required_capabilities.clear()
	enemy.tuning.bolt.allowed_modes.assign([&"submerged"])
	check(enemy.request_action(&"bolt").reason == &"movement_mode","AI actions use the same movement compatibility")
	enemy.tuning.bolt.allowed_modes.assign([&"grounded",&"airborne"])
	await Driver.start(enemy,&"boss_combo")
	check(enemy.actions.active_definition != null,"Boss patterns acquire shared action ownership")
	enemy.frozen = true
	check(enemy.actions.active_definition == null and enemy.actions.strikes.is_empty(),"Encounter freeze releases boss attack and strike ownership")
	enemy.frozen = false
	# Exercise the actual decision controller, not just manually requested attacks.
	await fresh()
	player.set_physics_process(false)
	player.invulnerable = true
	enemy.controller.manual = false
	enemy.controller.sequence = 0
	enemy.controller.approach_time = 0
	enemy.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.02,2.6)))
	var decisions: Array[StringName] = []
	enemy.actions.started.connect(func(id: StringName): decisions.append(id))
	for i in 420:
		await tick()
		if decisions.size() >= 2: break
	check(decisions.size() >= 2 and decisions[0] == &"boss_combo" and decisions[1] == &"boss_overhead","Normal AI still alternates combo and overhead at close range")
	check(enemy.actions.phase == enemy.actions.Phase.TELEGRAPH and enemy.marker.visible,"AI-selected overhead starts with its visible telegraph")
	enemy.actions.cancel(&"test_distance")
	enemy.controller.approach_time = 0
	enemy.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.02,15)))
	decisions.clear()
	for i in 180:
		await tick()
		if not decisions.is_empty(): break
	check(decisions.size() == 1 and decisions[0] == &"boss_lunge","Normal AI selects the existing lunge against a distant target")
	check(enemy.actions.phase == enemy.actions.Phase.TELEGRAPH and enemy.actions.timer < 0.02,"Distance pressure retains its windup before movement/damage")
	enemy.actions.cancel(&"test_cleanup")
	enemy.controller.manual = true
	var unload_request: RefCounted = enemy.request_action(&"bolt")
	var owner: RefCounted = enemy.actions
	enemy.queue_free()
	await process_frame
	check(unload_request.resolved and unload_request.reason == &"unload" and owner.pending_result == null and owner.active_definition == null,"AI unload resolves pending requests and releases ownership")
	stage.queue_free()
	await tick()
	print("OWNERSHIP: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
