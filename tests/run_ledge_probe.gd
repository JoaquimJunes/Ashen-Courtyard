extends "res://tests/fixtures/dodge_stage.gd"

func fixture(height: float = 1.5, width: float = 4, depth: float = 2) -> StaticBody3D:
	await prepare()
	p.set_physics_process(false)
	p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0.6,0.5)))
	var body := Shapes.solid(fixtures,Vector3(width,height,depth),Vector3(0,height/2,-depth/2),Color.GRAY)
	await settle(2)
	return body

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	var probe: RefCounted = p.traversal.probe
	for rate in [30,60,120]:
		await fixture()
		var candidate: RefCounted = probe.find(Vector3.FORWARD,1.0/rate)
		check(candidate != null and candidate.can_mantle,"%s Hz probe resolves handhold and standing route" % rate)
		if candidate != null:
			check(absf(candidate.lip.y-1.5) < 0.001 and absf(candidate.left_hand.distance_to(candidate.right_hand)-0.36) < 0.002,"Lip height and two hand supports match geometry")
			check(p.global_position == Vector3(0,0.6,0.5),"Probe never moves body")
	await fixture()
	var ceiling := Shapes.solid(fixtures,Vector3(4,0.2,1.9),Vector3(0,2.8,-1),Color.GRAY)
	await settle(2)
	var held: RefCounted = probe.find(Vector3.FORWARD,1.0/60)
	check(held != null and not held.can_mantle and held.reason == &"standing_blocked","Low top ceiling allows hang but rejects standing")
	ceiling.queue_free()
	await settle(2)
	check(probe.update_mantle(held),"Removing obstruction revalidates same handhold")
	await fixture(1.5,4,0.18)
	held = probe.find(Vector3.FORWARD,1.0/60)
	check(held != null and not held.can_mantle,"Thin rail can hold hands but cannot support standing capsule")
	await fixture(1.5,0.25)
	check(probe.find(Vector3.FORWARD,1.0/60) == null,"Narrow pillar rejects unsupported second hand")
	await fixture(4)
	check(probe.find(Vector3.FORWARD,1.0/60) == null,"Tall unreachable wall cannot attract the character")
	var body: StaticBody3D = await fixture()
	body.add_to_group(&"no_ledge_grab")
	check(probe.find(Vector3.FORWARD,1.0/60) == null,"Authored exclusion overrides geometric eligibility")
	body.remove_from_group(&"no_ledge_grab")
	fixtures.set_meta(&"no_ledge_grab",true)
	check(probe.find(Vector3.FORWARD,1.0/60) == null,"Parent-level exclusion is reusable for structures")
	fixtures.remove_meta(&"no_ledge_grab")
	check(probe.find(Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(45)),1.0/60) != null,"Diagonal approach inside cone is accepted")
	check(probe.find(Vector3.FORWARD.rotated(Vector3.UP,deg_to_rad(60)),1.0/60) == null,"Sideways approach outside cone is rejected")
	held = probe.find(Vector3.FORWARD,1.0/60)
	body.position.x += 0.1
	check(not held.valid(),"Surface motion invalidates static-only attachment")
	body.position.x -= 0.1
	body.queue_free()
	await settle(2)
	check(not held.valid(),"Deleted surface invalidates weak reference safely")
	# Wall face and top slab are separate scene pieces, like modular ruins.
	await fixture(1.3)
	Shapes.solid(fixtures,Vector3(4,0.2,2),Vector3(0,1.4,-1),Color.GRAY)
	await settle(2)
	held = probe.find(Vector3.FORWARD,1.0/60)
	check(held != null and held.can_mantle and held.surfaces.size() >= 2,"Modular wall/top colliders form one valid candidate")
	# Rotating the world does not introduce camera- or global-axis assumptions.
	await fixture()
	var rotated := Basis(Vector3.UP,0.63)
	fixtures.transform.basis = rotated
	p.motor.teleport(Transform3D(rotated,rotated*Vector3(0,0.6,0.5)))
	await settle(2)
	held = probe.find(rotated*Vector3.FORWARD,1.0/60)
	check(held != null and held.can_mantle and held.normal.dot(rotated*Vector3.BACK)>0.99,"Rotated surfaces retain local grip/route directions")
	await fixture()
	held = probe.find(Vector3.FORWARD,1.0/60)
	var short_arms: Resource = probe.definition.duplicate()
	short_arms.upper_arm_length = 0.10
	short_arms.forearm_length = 0.10
	probe.definition = short_arms
	check(not probe.arms_reach(held),"Gameplay grasp dimensions reject unreachable arm targets")
	probe.definition = p.traversal.definition
	p.traversal.candidate = held
	await settle(3)
	check(p.traversal.requirement("ledge_grab") == &"stale_ledge","An old query cannot acquire a new attachment")
	stage.queue_free()
	await settle(2)
	print("LEDGE PROBE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
