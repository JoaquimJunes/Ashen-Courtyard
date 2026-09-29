extends SceneTree
## External damage must not seed physical motion from a rendered interpolation.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var actor: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	actor.controller.manual = true
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.model.set_process(false)
	var skeleton: Skeleton3D = actor.model.skeleton
	var driver: RefCounted = actor.pose_driver
	var head: int = actor.model.rig.bone(skeleton,"Head")
	actor.reset_for_lab(Transform3D.IDENTITY)
	var reset_rotations: Array = driver.current.rotations.duplicate()
	var reset_positions: PackedVector3Array = driver.current.positions.duplicate()
	for phase in [0.2,0.65,0.9]:
		actor.model.animation.play("dodge/roll_forward",0)
		actor.model.animation.seek(phase,true)
		actor.model.animation.advance(0)
		driver.reset()
		actor.reset_for_lab(Transform3D.IDENTITY)
		var matches := true
		for bone in skeleton.get_bone_count():
			matches = matches and skeleton.get_bone_pose_rotation(bone).is_equal_approx(reset_rotations[bone]) and skeleton.get_bone_pose_position(bone).is_equal_approx(reset_positions[bone])
		check(matches and actor.model.base_clock == 0.0,"Reset seeds the same base pose regardless of previously sampled action")
	for alpha in [0.0,0.25,0.75,1.0]:
		actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,3,0)))
		actor.model.set_process(false)
		var committed := Quaternion(Vector3.RIGHT,0.2)
		skeleton.set_bone_pose_rotation(head,committed)
		driver.reset()
		skeleton.set_bone_pose_rotation(head,Quaternion(Vector3.UP,-0.5))
		driver.previous.capture(skeleton)
		driver.previous_actor_transform.origin.x -= 0.2
		driver.display(alpha)
		actor.velocity = Vector3.DOWN
		check(actor.take_damage(1,"external_handoff_"+str(alpha)) and actor.reactions.active,"External descending damage enters physical reaction")
		check(actor.reactions.driver.saved_model_transform.is_equal_approx(Transform3D.IDENTITY),"Physical parent frame excludes render interpolation at "+str(alpha))
		check(skeleton.get_bone_pose_rotation(head).is_equal_approx(committed),"Physical handoff uses committed joint pose at "+str(alpha))
		check(not driver.in_tick,"External handoff does not begin or end a simulation tick")
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,3,0)))
	driver.begin_tick()
	var fitted := Quaternion(Vector3.RIGHT,-0.35)
	skeleton.set_bone_pose_rotation(head,fitted)
	actor.reactions.begin(false,true)
	check(skeleton.get_bone_pose_rotation(head).is_equal_approx(fitted),"In-tick fitted traversal/dive pose survives handoff")
	check(driver.in_tick,"In-tick handoff preserves tick ownership until the character completes it")
	driver.end_tick()
	for alpha in [0.0,0.5]:
		actor.reset_for_lab(Transform3D.IDENTITY)
		actor.model.set_process(false)
		var committed := Quaternion(Vector3.RIGHT,0.2)
		skeleton.set_bone_pose_rotation(head,committed)
		driver.reset()
		skeleton.set_bone_pose_rotation(head,Quaternion(Vector3.UP,-0.5))
		driver.previous.capture(skeleton)
		driver.previous_actor_transform.origin.x -= 0.2
		driver.display(alpha)
		actor.motor.teleport(Transform3D(Basis(Vector3.UP,0.35),Vector3(20,4,7)))
		check(actor.model.transform.is_equal_approx(Transform3D.IDENTITY),"Raw teleport drops the old render countertransform")
		check(skeleton.get_bone_pose_rotation(head).is_equal_approx(committed),"Raw teleport preserves the committed local pose")
		check(driver.previous_actor_transform == driver.current_actor_transform and driver.current_actor_transform == actor.global_transform,"Raw teleport seeds both interpolation endpoints at its destination")
		var regions: Array = actor.hitboxes.regions
		var snapshot: Array = actor.hitboxes.query_snapshot()
		var aligned := true
		for index in regions.size():
			var expected: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(regions[index].bone)*regions[index].definition.local_transform
			aligned = aligned and snapshot[index].is_equal_approx(expected)
		check(aligned,"Hit geometry is reseeded after restoring the committed pose")
	actor.reset_for_lab(Transform3D.IDENTITY)
	driver.begin_tick()
	actor.model.position.y = 0.13
	skeleton.set_bone_pose_rotation(head,Quaternion(Vector3.RIGHT,-0.35))
	actor.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,3,0)))
	check(is_equal_approx(actor.model.position.y,0.13) and skeleton.get_bone_pose_rotation(head).is_equal_approx(Quaternion(Vector3.RIGHT,-0.35)),"In-tick teleport preserves the owner-sampled pose and frame")
	driver.end_tick()
	actor.reset_for_lab(Transform3D.IDENTITY)
	var boss: CharacterBody3D = load("res://scenes/boss.tscn").instantiate()
	world.add_child(boss)
	boss.controller.manual = true
	boss.set_physics_process(false)
	for inactive in ["normal","frozen","dead"]:
		boss.frozen = inactive == "frozen"
		boss.dead = inactive == "dead"
		boss._physics_process(1.0/60)
		check(not boss.pose_driver.in_tick,"Warden releases pose tick ownership after "+inactive+" update")
	world.free()
	print("POSE HANDOFF: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
