extends "res://tests/run_mantle.gd"
## Shared player, actual modular geometry and contact-driven completion.

func uneven_grab(offset: float, gap: float = 0, ceiling: bool = false) -> bool:
	p.controller.intent.movement = Vector3.ZERO
	p.controller.intent.surface_motion = Vector2.ZERO
	await prepare(Vector3(0,0.04,0.5))
	wall(1.5,0.30)
	var height := 1.5+offset
	Shapes.solid(fixtures,Vector3(4,height,3),Vector3(0,height/2,-1.8-gap),Color.GRAY)
	if ceiling:
		Shapes.solid(fixtures,Vector3(4,0.2,3),Vector3(0,height+1.25,-1.8),Color.GRAY)
	await settle(2)
	p.controller.intent.movement = Vector3.FORWARD
	if not await ActionTest.start(p,"jump"): return false
	for frame in Engine.physics_ticks_per_second*2:
		await settle(1)
		if p.traversal.status == &"hang": return true
		if p.is_on_floor() and not p.traversal.attached(): break
	return false

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for offset: float in [-0.6,-0.25,0,0.25,0.6]:
			var label := "%s Hz / %+0.2f m landing" % [rate,offset]
			var grabbed := await uneven_grab(offset)
			check(grabbed,"%s: original lip stays grabbable" % label)
			if not grabbed: continue
			check(p.traversal.candidate.can_mantle,"%s: supported route is available (%s)" % [label,p.traversal.candidate.reason])
			p.controller.intent.surface_motion = Vector2(0,1)
			for frame in rate*3:
				await settle(1)
				if not p.traversal.attached(): break
			p.controller.intent.movement = Vector3.ZERO
			p.controller.intent.surface_motion = Vector2.ZERO
			check(p.traversal.reason == &"completed" and p.movement.mode == &"grounded" and p.motor.last_result.grounded and not p.motor.tucked,"%s: pull-up finishes standing on real support (%s)" % [label,p.traversal.reason])
			check(absf(p.position.y-(1.5+offset)) < 0.035 and p.position.z < -0.3,"%s: feet settle on the destination rather than lip height" % label)
			check(p.stamina >= 75 and p.stamina <= 76,"%s: jump and pull-up pay once" % label)
			await settle(3)
			check(p.is_on_floor() and absf(p.position.y-(1.5+offset)) < 0.035,"%s: ordinary locomotion retains floor contact after the constrained move" % label)
	Engine.physics_ticks_per_second = 60
	for scenario in [{"offset":0.65,"gap":0.0,"ceiling":false}, {"offset":-0.65,"gap":0.0,"ceiling":false}, {"offset":0.25,"gap":0.24,"ceiling":false}, {"offset":0.25,"gap":0.0,"ceiling":true}]:
		check(await uneven_grab(scenario.offset,scenario.gap,scenario.ceiling),"Unsafe landing still permits the original supported hang")
		p.controller.intent.surface_motion = Vector2(0,1)
		await settle(90)
		check(p.traversal.status == &"hang" and p.stamina == 85,"Excess height, missing floor or ceiling rejects pull-up without spending: %s" % scenario)
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await settle(2)
	print("UNEVEN MANTLE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
