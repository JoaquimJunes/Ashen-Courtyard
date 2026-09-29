extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
const Intent = preload("res://features/character/character_intent.gd")
const Damage = preload("res://features/combat/damage_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
const EntityState = preload("res://features/world/persistent_entity_state.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)
func settle(frames: int = 3) -> void:
	for i in frames:
		await physics_frame
		await process_frame
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	Shapes.solid(host,Vector3(40,0.2,40),Vector3(0,-0.1,0),Color.GRAY)
	GameInput.configure()
	var session: Node = root.get_node("GameSession")
	var context: Node = session.configure_world(host)
	var a = session.create_player(host,context)
	var b = session.create_player(host,context)
	b.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	a.controller.manual = true
	b.controller.manual = true
	await settle(5)
	a.set_physics_process(false)
	b.set_physics_process(false)
	check(a.tuning == b.tuning and a.tuning.heavy == b.tuning.heavy,"Two characters share read-only definitions")
	check(a.resources != b.resources and a.actions != b.actions and a.motor != b.motor,"Runtime owners are unique per character")
	var original_stamina: float = a.stamina
	check(not a.resources.try_spend(30,101,1) and a.stamina == original_stamina and a.flasks == 3,"Failed mixed cost spends nothing")
	check(not a.resources.try_spend(-1,0) and not a.resources.try_spend(NAN,0) and not a.resources.try_spend(0,INF),"Invalid costs cannot credit or corrupt resources")
	check(a.resources.try_spend(20,15,1) and a.stamina == 80 and a.mana == 85 and a.flasks == 2,"Mixed costs spend atomically")
	check(b.stamina == 100 and b.mana == 100 and b.flasks == 3,"Spending does not mutate another character")
	a.reset_for_lab(Transform3D.IDENTITY)
	check(a.stamina == 100 and a.mana == 100 and a.health == 100 and a.flasks == 3,"Reset restores instance resources")
	check(not (await ActionTest.result(a,&"unknown")).accepted and a.actions.active_definition == null,"Unknown request returns rejection without ownership")
	check((await ActionTest.result(a,&"heavy")).accepted and a.stamina == 64,"Action controller accepts and owns a funded action")
	check((await ActionTest.result(a,&"cast")).reason == &"committed" and a.mana == 100,"Commitment rejection does not spend a second cost")
	check(b.state == b.State.FREE and b.actions.active_definition == null,"Actions and clocks are isolated")
	a.take_damage(1,"interrupt")
	check(a.actions.active_definition == null and a.actions.strike == null and a.state == a.State.FREE,"Damage during heavy charge releases action and strike ownership into guard")
	a.reset_for_lab(Transform3D.IDENTITY)
	# Replace only a's authoring profile for requirement/compatibility checks.
	a.tuning = a.tuning.duplicate()
	a.tuning.heavy = a.tuning.heavy.duplicate(true)
	a.actions.configure(a)
	a.tuning.heavy.required_capabilities.assign([&"test_unlock"])
	check((await ActionTest.result(a,&"heavy")).reason == &"missing_capability" and a.stamina == 100,"Definitions enforce required capabilities before spending")
	a.actions.capabilities.append(&"test_unlock")
	a.tuning.heavy.allowed_modes.assign([&"submerged"])
	check((await ActionTest.result(a,&"heavy")).reason == &"movement_mode" and a.stamina == 100,"Definitions reject unsupported movement modes")
	a.tuning.heavy.allowed_modes.assign([&"grounded",&"airborne"])
	a.tuning.heavy.interrupt_on_damage = false
	check((await ActionTest.result(a,&"heavy")).accepted,"Unlocked compatible definition can start")
	a.take_damage(1,"uninterruptible")
	check(a.state == a.State.HEAVY and a.actions.active_definition != null,"Damage respects the definition's interruption rule")
	a.take_damage(1000,"death")
	check(a.dead and a.actions.active_definition == null and a.actions.strike == null,"Death overrides commitment and releases all action ownership")
	a.reset_for_lab(Transform3D.IDENTITY)
	check(b.tuning.heavy.required_capabilities.is_empty() and b.tuning.heavy.interrupt_on_damage,"Edited private test definition leaves shared defaults unchanged")
	# Generic receivers have no boss brain or environment-specific parent API.
	var enemies: Array[Combatant] = []
	for x in [-1.0,1.0]:
		var enemy := Combatant.new()
		enemy.services = context
		host.add_child(enemy)
		enemy.setup(10000,preload("res://features/character/data/warden_body.tres"))
		enemy.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(x,0,-2)))
		enemies.append(enemy)
	await settle()
	var token := Strike.new()
	token.id = &"shared_strike"
	var request := Damage.new(10,token.id,token)
	check(enemies[0].receive_damage(request) and not enemies[0].receive_damage(request),"Token deduplicates damage throughout its lifetime")
	check(enemies[1].receive_damage(request),"One strike may hit multiple distinct enemies once")
	check(enemies[0].received.is_empty(),"Token strikes need no permanent receiver history")
	for i in 150: enemies[0].take_damage(1,"legacy_%s" % i)
	check(enemies[0].received.size() <= 128,"Legacy strike adapter has a hard size bound")
	enemies[0].tick_damage_history(8.1)
	check(enemies[0].received.is_empty(),"Legacy strike history expires in simulation time")
	var before_a: float = enemies[0].health
	var before_b: float = enemies[1].health
	context.cast(a,a.tuning.burst,a.get_aim(),Strike.new())
	check(enemies[0].health == before_a-a.tuning.burst_damage and enemies[1].health == before_b-a.tuning.burst_damage,"Burst reaches multiple receivers outside the courtyard")
	a.target = enemies[1]
	a.locked = true
	context.cast(a,a.tuning.bolt,a.get_aim(),Strike.new())
	var projectile: Node3D
	for child in host.get_children():
		if child.get_script() == preload("res://scripts/projectile.gd"): projectile = child
	check(projectile != null and projectile.direction.x > 0,"Locked spell aims at the selected enemy, not a single boss")
	context.clear()
	await settle()
	check(not is_instance_valid(projectile) and context.transients.is_empty(),"Context reset removes active projectiles and effects")
	# Intent enters the same player interface without keyboard input.
	a.reset_for_lab(Transform3D.IDENTITY)
	var intent := Intent.new()
	intent.movement = Vector3.RIGHT
	intent.sprint = true
	a.submit_intent(intent)
	a.set_physics_process(true)
	await settle(10)
	check(a.position.x > 0.05 and a.move_velocity.x > 0,"Scripted controller moves through the shared character motor")
	# Ongoing sprint exertion is charged before a new action can reserve stamina.
	a.resources.stamina = a.tuning.heavy_cost
	a.resources.stamina_wait = 1
	intent.action = &"heavy"
	await settle(1)
	check(a.state == a.State.FREE and a.stamina < a.tuning.heavy_cost,"Ongoing cost precedes a newly requested committed action")
	a.set_physics_process(false)
	intent.movement = Vector3.ZERO
	intent.sprint = false
	a.reset_for_lab(Transform3D.IDENTITY)
	a.set_physics_process(true)
	await settle(3)
	(await ActionTest.start(a,"dodge"))
	var actions: RefCounted = a.actions
	a.target = enemies[1]
	a.locked = true
	var before_unload: float = enemies[1].health
	context.cast(a,a.tuning.bolt,a.get_aim(),Strike.new())
	a.queue_free()
	await settle()
	check(actions.active_definition == null and not actions.forward_dive.active and actions.forward_dive.pose == null,"Unloading a character releases dive pose and action ownership")
	await settle(20)
	check(enemies[1].health == before_unload-b.tuning.bolt_damage,"A released projectile tolerates its caster unloading")
	var record := EntityState.new()
	record.entity_id = &"region_0/building_2/support_1"
	record.definition_id = &"stone_support"
	record.changes = {"broken":true}
	var saved: Dictionary = record.to_record()
	saved.changes.broken = false
	check(record.changes.broken and saved.entity_id == String(record.entity_id),"Persistence contract copies changes and uses stable IDs, not paths")
	host.queue_free()
	await settle()
	check(session.active_world == null,"World unload clears the session reference")
	print("ARCHITECTURE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
