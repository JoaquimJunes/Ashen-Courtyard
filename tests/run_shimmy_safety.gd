extends "res://tests/run_mantle.gd"

func turning() -> bool:
	p.controller.intent.surface_motion = Vector2.RIGHT
	for i in 300:
		await settle(1)
		if p.traversal.shimmy.corner_path != null and p.traversal.shimmy.corner_progress>0.35: return true
	return false

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	for condition in ["excluded","gap","height","obstruction"]:
		check(await start_grab(),"Prepare %s" % condition)
		match condition:
			"excluded":
				Shapes.solid(fixtures,Vector3(2,1.5,2),Vector3(3,0.75,-1),Color.GRAY).add_to_group(&"no_ledge_grab")
			"gap": Shapes.solid(fixtures,Vector3(2,1.5,2),Vector3(3.25,0.75,-1),Color.GRAY)
			"height": Shapes.solid(fixtures,Vector3(2,1.8,2),Vector3(3,0.9,-1),Color.GRAY)
			"obstruction": Shapes.solid(fixtures,Vector3(0.3,0.3,2),Vector3(1.1,1.65,0.4),Color.GRAY)
		await settle(2)
		p.controller.intent.surface_motion = Vector2.RIGHT
		await settle(300)
		check(p.traversal.attached() and p.position.x<1.84,"%s stops at supported grip rather than crossing or dropping (%s)" % [condition,p.position])
		check(p.stamina==85 and p.health==100,"Blocked sideways input does not spend or injure")
		p.controller.intent.surface_motion = Vector2.LEFT
		var before := p.position
		await settle(40)
		check(p.position.x<before.x-0.1,"Can move away from %s after rejection" % condition)
	check(await start_grab(),"Prepare corner pause/reversal")
	check(await turning(),"Enter outside corner")
	p.controller.intent.surface_motion = Vector2.ZERO
	var at := p.position
	var turn: float = p.traversal.shimmy.corner_progress
	await settle(20)
	check(p.position.distance_to(at)<0.001 and p.traversal.shimmy.corner_progress==turn,"Releasing input holds halfway around corner")
	paused = true
	for i in 8: await process_frame
	check(p.position==at,"Pause cannot advance corner progress")
	paused = false
	p.controller.intent.surface_motion = Vector2.LEFT
	await settle(90)
	check(p.traversal.attached() and p.traversal.candidate.normal.dot(Vector3.BACK)>0.99 and p.position.x<1.85,"Opposite input reverses onto original edge")
	check(await start_grab(),"Prepare corner pull-up")
	check(await turning(),"Enter corner for pull-up")
	p.controller.intent.surface_motion = Vector2(0,1)
	for i in 110:
		await settle(1)
		if p.traversal.reason==&"completed": break
	check(p.traversal.reason==&"completed" and p.position.y>1.49,"Forward can pull up from a validated corner hold (%s / %s)" % [p.traversal.reason,p.position])
	check(await start_grab(),"Prepare corner let-go")
	check(await turning(),"Enter corner for release")
	var cost: float = p.stamina
	p.controller.intent.surface_motion = Vector2.ZERO
	p.request_action(&"dodge")
	await settle(2)
	check(not p.traversal.attached() and p.velocity.y<0 and p.stamina==cost and not p.invulnerable,"Dodge lets go during corner without cost or immunity")
	check(await start_grab(),"Prepare corner hit")
	check(await turning(),"Enter corner for damage")
	p.take_damage(5,"shimmy_hit")
	await settle(2)
	check(p.reactions.active and p.traversal.shimmy.corner_path==null and not p.traversal.attached(),"Accepted hit releases corner ownership into ragdoll")
	check(await start_grab(),"Prepare removed corner")
	check(await turning(),"Enter corner before deleting support")
	var held: Node3D = p.traversal.candidate.surfaces[0].get_ref()
	held.queue_free()
	await settle(3)
	check(not p.traversal.attached() and p.traversal.shimmy.corner_path==null,"Deleted supporting surface clears route and falls normally")
	check(await start_grab(),"Prepare reset/unload")
	check(await turning(),"Enter corner for reset")
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(6,0.04,0)))
	check(p.traversal.shimmy.corner_path==null and p.traversal.shimmy.pending==null and p.stamina==100,"Reset clears requests, corner progress, and resource state")
	var input := preload("res://features/character/input_controller.gd").new()
	Input.action_press("right")
	for yaw: float in [0,PI/2,PI]: check(input.sample(yaw).surface_motion.x>0.99,"Right remains ledge-relative after camera orbit")
	Input.action_release("right")
	check(await start_grab(),"Prepare zero-stamina shimmy")
	p.stamina = 0
	p.controller.intent.surface_motion = Vector2.RIGHT
	await settle(60)
	check(p.position.x>0.60 and p.stamina==0 and p.traversal.attached(),"Zero stamina still permits unpaid hanging movement")
	check(await start_grab(),"Prepare two instances / unload during corner")
	check(await turning(),"Enter corner before second instance")
	var second: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	second.controller.manual = true
	stage.add_child(second)
	second.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(8,0.04,0)))
	await settle(3)
	check(second.traversal.shimmy.definition==p.traversal.shimmy.definition and second.traversal.shimmy.corner_path==null and second.stamina==100,"Shared tuning never shares corner progress or costs")
	var owner: RefCounted = p.traversal.shimmy
	var lease: RefCounted = p.movement.attachment
	p.queue_free()
	await settle(3)
	check(owner.corner_path==null and owner.pending==null and not lease.valid() and lease.motion==null and lease.token==0,"Unloading revokes held attachment and all pending corner state")
	stage.queue_free()
	await settle(2)
	var lab: Node3D = load("res://scenes/movement_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	p = lab.player
	p.controller.manual = true
	lab.start_ledge_corner_test(1)
	await settle(8)
	p.controller.intent.movement = Vector3.FORWARD
	await ActionTest.start(p,"jump")
	await settle(35)
	check(p.traversal.status==&"hang","Production corner course uses shared jump/grab")
	p.controller.intent.surface_motion = Vector2.RIGHT
	await settle(270)
	check(p.traversal.attached() and p.traversal.candidate.normal.x<-.99,"Production lab inside corner is traversable")
	lab.reset_station()
	await settle(5)
	check(not p.traversal.attached() and p.traversal.shimmy.corner_path==null and p.stamina==100,"Lab reset restores normal character")
	lab.queue_free()
	await settle(2)
	print("SHIMMY SAFETY: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
