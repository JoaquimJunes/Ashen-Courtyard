extends SceneTree
const Stage = preload("res://tests/fixtures/swim_stage.gd")
var checks := 0
var failures := 0
var stage: Stage
var p: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func aligned(label: String) -> void:
	var model: Node3D = p.model
	var skeleton: Skeleton3D = model.skeleton
	var head: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(model.rig.bone(skeleton,"Head"))
	var torso: Vector3 = (skeleton.global_transform*skeleton.get_bone_global_pose(model.rig.bone(skeleton,"Body"))).origin
	var capsule: Transform3D = p.motor.shape_node.global_transform
	check(capsule.basis.y.dot((head.origin-torso).normalized()) > 0.999,label+": capsule follows visible torso/head axis")
	var head_local: Vector3 = capsule.affine_inverse()*head.origin
	var torso_local: Vector3 = capsule.affine_inverse()*torso
	check(Vector2(head_local.x,head_local.z).length() < 0.001 and Vector2(torso_local.x,torso_local.z).length() < 0.001,label+": capsule center follows body, including horizontal offsets")
	check(p.hitboxes.breathing_position().distance_to(head*p.hitboxes.profile.breathing_offset) < 0.0001,label+": breath samples the completed visible head")
	var matches := true
	for region in p.hitboxes.regions:
		var expected: Transform3D = skeleton.global_transform*skeleton.get_bone_global_pose(region.bone)*region.definition.local_transform
		matches = matches and p.hitboxes.world_transform(region).is_equal_approx(expected)
	check(matches,label+": all fitted regions follow the same completed pose")

func run() -> void:
	stage = Stage.new()
	root.add_child(stage)
	current_scene = stage
	p = stage.player
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await stage.reset_at()
		aligned("%s float" % rate)
		check(p.hitboxes.breathing_position().y > 0.02 and not p.swimming.head_detector.head_submerged,"Floating mouth has air")
		await stage.reset_at(Vector3(3,-2.7,0))
		for heading: Vector3 in [Vector3.FORWARD,Vector3(1,-0.3,0).normalized(),Vector3(-1,0.4,0).normalized(),Vector3.ZERO]:
			stage.intent.swim_direction = heading
			stage.intent.movement = Vector3(heading.x,0,heading.z)
			await stage.tick(0.35)
			aligned("%s heading %s" % [rate,heading])
			var clock: float = p.model.animation.current_animation_position
			var pose_clock: int = p.presentation.swim.pose_ticks
			var pose: Array = p.presentation.capture_pose()
			for render_delta in [1.0/24,1.0/60,1.0/144,1.0/240]: p.model.update_pose(render_delta)
			check(is_equal_approx(clock,p.model.animation.current_animation_position) and pose_clock == p.presentation.swim.pose_ticks and pose == p.presentation.capture_pose(),"Render rate cannot advance or replace the water pose")
			aligned("%s after render" % rate)
		check(p.swimming.head_detector.head_submerged and p.resources.breath < 20,"Pitched head underwater consumes breath")
		# Enclose an already prone swimmer with real geometry, then request idle.
		await stage.reset_at(Vector3(3,-2.7,0))
		stage.intent.swim_direction = Vector3.FORWARD
		stage.intent.movement = Vector3.FORWARD
		await stage.tick(0.65)
		var center: Vector3 = p.motor.shape_node.global_position
		var half: float = p.motor.capsule.radius+absf(p.motor.shape_node.global_basis.y.y)*(p.motor.capsule.height*0.5-p.motor.capsule.radius)
		var ceiling := Shapes.solid(stage,Vector3(4,0.2,4),center+Vector3.UP*(half+0.105),Color.GRAY)
		var floor := Shapes.solid(stage,Vector3(4,0.2,4),center-Vector3.UP*(half+0.105),Color.GRAY)
		stage.intent.swim_direction = Vector3.ZERO
		stage.intent.movement = Vector3.ZERO
		await stage.tick(0.6)
		check(absf(p.motor.shape_node.global_basis.y.y) < 0.8,"%s: blocked idle stays compatible with prone clearance" % rate)
		aligned("%s blocked transition" % rate)
		var query: PhysicsShapeQueryParameters3D = p.motor.shape_query(p.global_transform,p.motor.capsule.height,0)
		query.transform = p.motor.shape_node.global_transform
		query.margin = 0
		check(p.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(),"Blocked rotation does not overlap floor or ceiling")
		stage.intent.swim_direction = Vector3.BACK
		stage.intent.movement = Vector3.BACK
		var before: Vector3 = p.position
		await stage.tick(1.8)
		check(p.position.distance_to(before) > 2.5,"%s: blocked swimmer can turn and escape" % rate)
		ceiling.free()
		floor.free()
		stage.intent.swim_direction = Vector3.ZERO
		stage.intent.movement = Vector3.ZERO
		await stage.tick(0.5)
		aligned("%s clear idle" % rate)
		check(absf(p.motor.shape_node.global_basis.y.y) > 0.8,"Clear water allows upright tread")
		var ticks: int = p.presentation.swim.pose_ticks
		paused = true
		for i in 4: await process_frame
		check(ticks == p.presentation.swim.pose_ticks,"Pause freezes physics-owned water animation")
		paused = false
		await stage.reset_at(Vector3(-9,-0.4,0))
		check(not p.motor.swimming_posture and p.model.transform.is_equal_approx(Transform3D.IDENTITY) and not p.presentation.swim.was_swimming,"Dry reset clears both posture owners")
	stage.queue_free()
	await process_frame
	print("SWIMMING ALIGNMENT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
