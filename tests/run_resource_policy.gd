extends "res://tests/fixtures/dodge_stage.gd"
const Policy = preload("res://features/character/resource_regeneration_policy.gd")

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	await prepare()
	p.stamina = 50
	p.stamina_wait = 0
	await settle(6)
	check(p.stamina > 50,"Ground support permits ordinary regeneration")
	check(not Policy.stamina_allowed(p,p.movement,false) and not Policy.stamina_allowed(p,p.movement,true,true),"Committed actions and reactions retain regeneration restrictions")
	await prepare(Vector3(0,12,0))
	p.stamina = 40
	p.stamina_wait = 0
	await settle(12)
	check(p.stamina == 40 and p.movement.mode == &"airborne","Airborne free action cannot regenerate")
	check(p.resources.try_spend(10) and p.stamina == 30,"Airborne explicit costs still apply atomically")
	check(not p.resources.try_spend(31,1) and p.stamina == 30 and p.mana == 100,"Failed combined payment does not partially spend")
	await prepare()
	p.stamina = 0
	p.stamina_wait = 0
	await settle(1)
	check(p.stamina > 0 and p.stamina < 2,"Grounding resumes normal rate without banked regeneration")
	stage.queue_free()
	await settle(2)
	print("RESOURCE POLICY: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
