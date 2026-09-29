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
		for speed: float in [0,4.8,7.4]:
			for angle: float in [-40,0,40]:
				p.controller.intent.movement = Vector3.ZERO
				p.controller.intent.surface_motion = Vector2.ZERO
				await prepare(Vector3(0,0.04,0.5))
				wall()
				await settle(2)
				var heading := Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(angle))
				p.controller.intent.movement = heading
				p.motor.move_velocity = heading*speed
				await ActionTest.start(p,"jump")
				var trace: Array[String] = []
				var last := ""
				for i in rate*2:
					await settle(1)
					var value: String = str(p.traversal.status)+" "+str(p.traversal.reason)
					if value != last:
						trace.append("%s %s" % [p.position,value])
						last = value
					if p.traversal.status == &"hang": break
				if p.traversal.status != &"hang": print("TRACE ",rate," ",speed," ",angle," ",trace)
				check(p.traversal.status == &"hang","%s Hz / %.1f m/s / %.0f degrees catches ledge" % [rate,speed,angle])
	Engine.physics_ticks_per_second = 60
	for speed: float in [-1,-10]:
		p.controller.intent.movement = Vector3.ZERO
		await prepare(Vector3(0,0.04,0.5))
		wall()
		p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.6,0.5)))
		p.velocity.y = speed
		p.controller.intent.movement = Vector3.FORWARD
		p.movement.ledge_jump = speed < -7.5
		await settle(2)
		check(not p.traversal.attached(),"Ordinary fall or excessive descent cannot auto-catch")
	Engine.physics_ticks_per_second = original
	stage.queue_free()
	await settle(2)
	print("LEDGE APPROACH: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
