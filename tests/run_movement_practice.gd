extends SceneTree
const Driver = preload("res://tests/action_test_driver.gd")
const Strike = preload("res://features/combat/strike_token.gd")
const Intent = preload("res://features/character/character_intent.gd")
var checks := 0
var failures := 0
var lab: Node3D
var player: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick(count: int = 1) -> void:
	for i in count:
		await physics_frame
		await process_frame
func reset_dive() -> void:
	lab.reset_station()
	player.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(5,0.02,5)))
	player.submit_intent(Intent.new())
	await tick(4)
func run() -> void:
	lab = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	player = lab.player
	player.controller.manual = true
	await tick(6)
	check(lab.practice.mode == 0 and not player.combat_enabled and not is_instance_valid(lab.practice.target),"Ordinary laboratory remains combat-free by default")
	lab.hud.toggle_pause()
	lab.hud.menu.navigate("Test Grounds")
	lab.hud.menu.navigate("Practice")
	check(paused and lab.hud.practice_options.visible and lab.hud.practice_options.instructions.text.contains(GameInput.key("dodge")),"Review menu opens paused and displays the saved dodge binding")
	lab.hud.practice_options.mode_selector.select(1)
	lab.hud.practice_options.start_hub()
	await tick(6)
	check(not paused and not lab.hud.practice_options.visible and player.combat_enabled and player.target == lab.practice.target,"Starting hub practice creates and assigns an explicit target")
	check(lab.practice.target.tuning.boss_health == 200 and lab.practice.target.tuning.combat.boss_overhead.damage == 10 and load("res://data/combat.tres").boss_health == 1500 and load("res://data/combat.tres").combat.boss_overhead.damage == 36,"Practice profile cannot mutate shared courtyard boss definitions (%s/%s, shared %s/%s)" % [lab.practice.target.tuning.boss_health,lab.practice.target.tuning.combat.boss_overhead.damage,load("res://data/combat.tres").boss_health,load("res://data/combat.tres").combat.boss_overhead.damage])
	await tick(120)
	check(player.health == 100 and lab.practice.target.actions.active_definition == null,"Stationary target never attacks on its own")
	player.targeting.toggle()
	check(player.locked,"Optional practice target supports the existing camera lock")
	await Driver.start(player,&"light")
	await tick(60)
	check(lab.practice.target.health < 200,"Player melee damages the practice target through shared combat")
	check(lab.review.description().contains("light: accepted"),"Diagnostics report the real action request result")
	lab.reset_station()
	await tick(6)
	check(player.health == 100 and player.stamina == 100 and lab.practice.target.health == 200 and player.target == lab.practice.target and lab.review.last_request == "None","Station reset restores both characters, targeting and diagnostics")
	# Every forward-dive phase is vulnerable outside its authored immunity window.
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for phase in [0,1,2]:
			await reset_dive()
			await Driver.start(player,&"dodge")
			for i in rate*2:
				if player.forward_dive.active and player.forward_dive.phase == phase and not player.invulnerable: break
				await tick()
			check(player.forward_dive.active and player.forward_dive.phase == phase,"%s Hz reaches vulnerable dive phase %s" % [rate,phase])
			var hit: bool = lab.services.deal(lab.practice.target,player,10,Strike.new())
			check(hit and player.health == 90 and player.state == player.State.HURT and player.actions.active_definition == null and player.forward_dive.pose == null and player.model.is_processing(),"%s Hz phase %s damage releases movement/pose ownership" % [rate,phase])
			await tick(rate)
			check(player.state == player.State.FREE and player.is_on_floor(),"%s Hz phase %s interruption recovers to supported movement" % [rate,phase])
		await reset_dive()
		await Driver.start(player,&"dodge")
		for i in rate:
			if player.invulnerable: break
			await tick()
		check(player.invulnerable and not lab.services.deal(lab.practice.target,player,10,Strike.new()) and player.health == 100,"%s Hz dive immunity rejects real shared damage" % rate)
		var position := player.position
		var clock: float = player.timer
		paused = true
		await tick(4)
		check(player.position == position and player.timer == clock,"%s Hz pause freezes a practice dodge" % rate)
		paused = false
	Engine.physics_ticks_per_second = original_rate
	lab.set_practice_mode(2)
	await tick(4)
	check(lab.practice.target.state == lab.practice.target.State.TELEGRAPH and lab.practice.target.marker.visible and player.health == 100,"Timed practice visibly telegraphs before dealing damage")
	for i in 120:
		await tick()
		if player.health < 100: break
	check(player.health == 90 and player.state == player.State.HURT,"Timed overhead uses the real attack window and deals 10 damage")
	await tick(20)
	check(player.health == 90,"One overhead strike cannot damage repeatedly")
	lab.set_practice_mode(1)
	await tick(6)
	var reset_count: int = lab.reset_count
	player.take_damage(1000,"practice_death")
	await tick(6)
	check(not player.dead and player.health == 100 and player.stamina == 100 and player.flasks == 3 and lab.reset_count == reset_count+1 and player.target == lab.practice.target,"Player death resets the current practice attempt without courtyard end logic")
	lab.practice.target.take_damage(1000,"target_death")
	await tick(2)
	check(lab.practice.target.dead and lab.practice.target.actions.active_definition == null and lab.practice.status().contains("DEFEATED"),"Defeated target stops acting and offers reset")
	lab.reset_station()
	await tick(4)
	check(not lab.practice.target.dead and lab.practice.target.health == 200,"Reset restores a defeated target")
	for i in 3:
		await Driver.start(player,&"cast")
		await tick(30)
		lab.reset_station()
		await tick(4)
		check(lab.services.transients.is_empty() and player.mana == 100 and player.actions.active_definition == null and lab.practice.get_child_count() == 4,"Repeated reset %s clears projectiles, costs and old targets" % i)
	var pending: RefCounted = player.request_action(&"heavy")
	lab.reset_station()
	await tick(4)
	check(pending.resolved and pending.reason == &"reset" and lab.review.last_request == "None" and player.actions.active_definition == null,"Reset resolves pending input and clears its old diagnostic result")
	lab.set_practice_mode(1)
	player.reset_for_lab(Transform3D(Basis(Vector3.UP,-PI/2),Vector3(19,0.02,10)))
	await tick(4)
	await Driver.start(player,&"dodge")
	for i in 60:
		await tick()
		if lab.practice.mode == 0: break
	check(lab.practice.mode == 0 and player.forward_dive.active and player.state == player.State.DODGE,"Leaving practice during a dive does not cancel traversal")
	await tick(75)
	check(absf(player.position.x-24.5) < 0.06 and player.state == player.State.FREE,"Dive keeps its full travel budget across the hub boundary")
	lab.set_practice_mode(1)
	player.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(21,0.02,0)))
	await tick(3)
	check(lab.practice.mode == 0 and not player.combat_enabled and player.target == null and not is_instance_valid(lab.practice.target),"Walking out of the hub into an aisle disables and removes practice")
	lab.set_practice_mode(2)
	lab.go_to_station(1)
	await tick(3)
	check(lab.active_station == 1 and lab.practice.mode == 0 and not player.combat_enabled,"Station navigation removes hub combat")
	lab.set_practice_mode(2)
	lab.reset_all()
	await tick(3)
	check(lab.active_station == 0 and lab.practice.mode == 0 and not player.combat_enabled and player.rig.subject == player,"Entire-lab reset returns to free movement with camera follow")
	lab.queue_free()
	await process_frame
	await process_frame
	print("MOVEMENT PRACTICE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
