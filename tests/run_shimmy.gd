extends "res://tests/run_mantle.gd"

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var original := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for side: float in [-1,1]:
			check(await start_grab(),"%s Hz prepare lateral hang" % rate)
			var origin := p.position
			var stamina: float = p.stamina
			p.controller.intent.surface_motion = Vector2(side,0)
			await settle(rate)
			var travelled: float = (p.position-origin).x*side
			check(travelled>0.60 and travelled<0.78,"%s Hz side %.0f: smooth deliberate travel (%.3f m)" % [rate,side,travelled])
			check(p.traversal.attached() and absf(p.position.y-origin.y)<0.002 and p.stamina==stamina,"Shimmy retains support and unchanged stamina")
			p.controller.intent.surface_motion = Vector2.ZERO
			origin = p.position
			await settle(8)
			check(p.position.distance_to(origin)<0.001,"Releasing lateral input stops safely")
			p.controller.intent.surface_motion = Vector2(side,0)
			for i in rate*5:
				await settle(1)
				if p.traversal.candidate.normal.dot(Vector3.RIGHT*side)>0.99: break
			check(p.traversal.attached() and p.traversal.candidate.normal.dot(Vector3.RIGHT*side)>0.99,"%s Hz: outside corner rounds to next face (pos %s / %s)" % [rate,p.position,p.traversal.reason])
			check(p.stamina==stamina and p.actions.active_definition==null,"Corner keeps persistent hang, without an action cost")
			# Concave L, mirrored for the opposite direction.
			check(await start_grab(),"Prepare inside corner")
			Shapes.solid(fixtures,Vector3(1.0,1.5,4),Vector3(side*2.5,0.75,1),Color.GRAY)
			await settle(2)
			p.controller.intent.surface_motion = Vector2(side,0)
			for i in rate*5:
				await settle(1)
				if p.traversal.candidate.normal.dot(Vector3.LEFT*side)>0.99: break
			check(p.traversal.attached() and p.traversal.candidate.normal.dot(Vector3.LEFT*side)>0.99,"%s Hz: inside corner turns without cutting through wall (%s / %s)" % [rate,p.position,p.traversal.reason])
	Engine.physics_ticks_per_second = original
	stage.queue_free()
	await settle(2)
	print("SHIMMY: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
