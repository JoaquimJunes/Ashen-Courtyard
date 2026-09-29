extends SceneTree
const Stage = preload("res://tests/fixtures/swim_stage.gd")
const Intent = preload("res://features/character/character_intent.gd")
const Damage = preload("res://features/combat/damage_request.gd")
var checks := 0
var failures := 0
var stage: Stage

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	current_scene = stage
	var p: CharacterBody3D = stage.player
	var old_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await stage.reset_at(Vector3(3,-2.5,0))
		p.resources.breath = 0.2
		p.combat_enabled = false
		p.invulnerable = true
		await stage.tick(1.2)
		check(p.resources.breath == 0 and is_equal_approx(p.health,90) and p.actions.is_available(),"%s: drowning bypasses lab combat toggle without stagger" % rate)
		p.resources.breath = 0
		p.swimming.drowning_clock = 0
		p.resources.health = 10
		var deaths := [0]
		var death_listener := func(): deaths[0] += 1
		p.died.connect(death_listener)
		await stage.tick(1.1)
		check(p.dead and deaths[0] == 1 and not p.reactions.active,"%s: drowning death once without underwater get-up" % rate)
		p.died.disconnect(death_listener)
		await stage.reset_at(Vector3(3,-2.5,0))
		p.resources.breath = 1
		stage.intent.swim_vertical = 1
		await stage.tick(4.5)
		check(p.resources.breath > 19.9 and not p.swimming.underwater,"%s: resurfacing refills breath" % rate)
		for action in ["light","heavy","cast","heal","jump","crouch","dodge","use_gadget"]:
			var before: float = p.stamina
			var rejected: RefCounted = p.actions.request(action,true)
			check(rejected.resolved and not rejected.accepted and p.stamina == before and p.actions.pending_result == null,"%s: reject water action %s without buffering or cost" % [rate,action])
		await stage.reset_at(Vector3(3,-2.5,0))
		stage.intent.swim_vertical = -1
		await stage.tick(0.2)
		p.receive_damage(Damage.new(5,StringName("swim_hit_%s" % rate)))
		check(not p.reactions.active and p.health == 95 and p.state == p.State.HURT,"%s: descending hit stays in swim hurt recovery" % rate)
		await stage.tick(0.6)
		check(p.actions.is_available() and p.swimming.active,"%s: control returns after hurt" % rate)
		await stage.reset_at(Vector3(3,-2.5,0))
		var before_breath: float = p.resources.breath
		var before_position: Vector3 = p.position
		paused = true
		for index in 5: await process_frame
		check(p.position == before_position and p.resources.breath == before_breath,"%s: pause stops movement and breath" % rate)
		paused = false
		await stage.tick(0.2)
		check(p.resources.breath < before_breath,"%s: resume continues breath" % rate)
		for index in 3:
			await stage.reset_at(Vector3(-9,-0.4,0))
			check(not p.swimming.active and p.resources.breath == 20 and not p.motor.swimming_posture and p.motor.shape_node.basis.is_equal_approx(Basis.IDENTITY),"%s: repeated reset restores breath and standing shape" % rate)
			await stage.reset_at(Vector3(3,-2.5,0))
		# Use actual input mapping; no new duplicate bindings are introduced.
		p.controller.manual = false
		var old_key: int = GameInput.bindings.crouch
		GameInput.bindings.crouch = KEY_V
		GameInput.apply()
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		await stage.tick(0.15)
		check(p.controller.intent.swim_vertical == -1 and not p.posture.crouched,"%s: rebound crouch dives without changing land stance" % rate)
		key.pressed = false
		Input.parse_input_event(key)
		GameInput.bindings.crouch = old_key
		GameInput.apply()
		p.controller.manual = true
		await stage.reset_at(Vector3(3,-2,0))
		p.reactions.begin(false,true)
		await stage.tick(0.2)
		check(not p.reactions.active and p.swimming.active and not p.motor.ragdoll_motion,"%s: living ragdoll safely hands back to swimming" % rate)
	Engine.physics_ticks_per_second = old_rate
	await stage.reset_at(Vector3(3,-2.5,0))
	var other := preload("res://scenes/player.tscn").instantiate()
	other.position = Vector3(8,-1.1,0)
	other.controller.manual = true
	stage.add_child(other)
	p.resources.breath = 5
	await stage.tick(0.3)
	check(other.resources.breath == 20 and p.resources.breath < 5 and other.swimming != p.swimming,"Two characters have independent immersion and breath")
	var swim: RefCounted = p.swimming
	stage.queue_free()
	await process_frame
	check(not swim.active and swim.water == null,"Unload releases water state")
	print("SWIMMING LIFECYCLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
