extends SceneTree
const Stage = preload("res://tests/fixtures/swim_stage.gd")
const Damage = preload("res://features/combat/damage_request.gd")
var checks := 0
var failures := 0
var stage: Stage
var p: CharacterBody3D
var starts: Array[StringName] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	if pressed: Input.action_press("light")
	else: Input.action_release("light")
	p._unhandled_input(event)

func crouch_key(pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_C
	event.pressed = pressed
	# Timed posture input is sampled in physics; dispatch the actual device edge.
	Input.parse_input_event(event)

func reset_attack() -> void:
	Input.action_release("light")
	await stage.reset_at(Vector3(3,0.41,-9))
	p.controller.manual = false
	starts.clear()

func run() -> void:
	GameInput.loaded = true
	GameInput.bindings = GameInput.DEFAULTS.duplicate()
	GameInput.apply()
	stage = Stage.new()
	root.add_child(stage)
	current_scene = stage
	p = stage.player
	p.actions.started.connect(func(id): starts.append(id))
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await stage.reset_at(Vector3(3,0.41,-9))
		check(p.posture.toggle() == &"" and p.motor.capsule.height <= 1.0,"%s: crouch collision is immediately at most 1m" % rate)
		var tunnel := Shapes.solid(stage,Vector3(2,0.2,2),Vector3(0,1.51,-9),Color.GRAY)
		await physics_frame
		stage.intent.movement = Vector3.LEFT
		await stage.tick(1.5)
		check(p.position.x < 0.8,"%s: actual movement enters a 1.01m-high tunnel" % rate)
		check(not p.posture.stand(),"%s: low tunnel prevents standing" % rate)
		tunnel.queue_free()
		await process_frame
		await reset_attack()
		button(true)
		await stage.tick(0.1)
		check(starts.is_empty(),"%s: press waits to distinguish tap from hold" % rate)
		button(false)
		await stage.tick(0.05)
		check(starts == [&"light"],"%s: short left click starts one light attack" % rate)
		await reset_attack()
		button(true)
		await stage.tick(0.3)
		check(starts == [&"heavy"] and p.actions.heavy_charging(),"%s: holding begins the heavy pullback charge" % rate)
		check(p.stamina == p.tuning.stamina_max-p.tuning.heavy.stamina_cost,"%s: charge pays its action cost once" % rate)
		await stage.tick(0.55)
		check(starts == [&"heavy"] and p.state == p.State.HEAVY,"%s: full charge automatically commits heavy while held" % rate)
		check(is_equal_approx(p.stamina,p.tuning.stamina_max-p.tuning.heavy.stamina_cost),"%s: heavy pays once through normal lifecycle" % rate)
		await stage.tick(2)
		button(false)
		await stage.tick(0.1)
		check(starts == [&"heavy"],"%s: continued hold and release cannot repeat or add light" % rate)
		await reset_attack()
		p.stamina = 0
		p.stamina_wait = 10
		button(true)
		await stage.tick(1)
		button(false)
		await stage.tick(0.1)
		check(starts.is_empty() and p.stamina == 0,"%s: unaffordable charge never falls back to light" % rate)
		await reset_attack()
		button(true)
		await stage.tick(0.2)
		p.receive_damage(Damage.new(1,&"charge_interruption"))
		await stage.tick(1)
		button(false)
		await stage.tick(0.1)
		check(starts == [&"heavy"] and p.actions.is_available(),"%s: damage cancels charge without a follow-up" % rate)
		await reset_attack()
		button(true)
		await stage.tick(0.2)
		paused = true
		var charge: float = p.timer
		for i in 3: await process_frame
		check(p.timer == charge,"%s: pause freezes charge" % rate)
		button(false)
		paused = false
		await stage.tick(0.8)
		check(starts == [&"heavy"] and p.actions.is_available(),"%s: releasing in menu cancels charge on resume" % rate)
		await reset_attack()
		button(true)
		await stage.tick(0.2)
		p.reset_for_lab(p.global_transform)
		await stage.tick(0.8)
		button(false)
		check(starts == [&"heavy"] and p.actions.is_available(),"%s: reset clears a held charge" % rate)
		# Real floors measure wading boundaries, including solver contact margins.
		for depth in [0.99,1.0,1.2,1.29,1.3,1.4]:
			var floor_body := Shapes.solid(stage,Vector3(4,0.3,4),Vector3(3,-depth-0.15,2),Color.GRAY)
			await physics_frame
			await stage.reset_at(Vector3(3,-depth+0.005,2))
			check(p.swimming.active == (depth >= 1.3),"%s: automatic swim threshold at %.2fm" % [rate,depth])
			if depth < 1.3:
				p.controller.manual = false
				crouch_key()
				await stage.tick(0.1)
				crouch_key(false)
				check(p.swimming.active == (depth >= 1.0),"%s: C swim threshold at %.2fm" % [rate,depth])
				if depth < 1.0: check(p.posture.crouched,"Below 1m C retains land crouch")
			if depth >= 1.0:
				await stage.tick(0.6)
				check(p.swimming.active,"%s: floating persists after entry at %.2fm" % [rate,depth])
			floor_body.queue_free()
			await process_frame
	Engine.physics_ticks_per_second = original_rate
	Input.action_release("light")
	stage.queue_free()
	await process_frame
	print("GAMEPLAY TUNING: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
