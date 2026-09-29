extends "res://tests/fixtures/dodge_stage.gd"
const IK = preload("res://features/presentation/limb_ik.gd")

func world_pose() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in p.model.skeleton.get_bone_count():
		result.append(p.model.skeleton.global_transform*p.model.skeleton.get_bone_global_pose(bone))
	return result

func lying_pose(tilt: Basis) -> Array[Transform3D]:
	p.model.animation.play("k_idle")
	p.model.animation.seek(0,true)
	p.model.animation.advance(0)
	p.model.skeleton.force_update_all_bone_transforms()
	var poses := world_pose()
	var pivot: Vector3 = poses[p.model.rig.bone(p.model.skeleton,"Body")].origin
	var transform := Transform3D(tilt,Vector3(0,0.32,0)-tilt*pivot)
	for bone in poses.size(): poses[bone] = transform*poses[bone]
	return poses

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	stage.add_child(p)
	await prepare()
	check(is_equal_approx(p.reactions.definition.get_up_seconds,1.2),"Approved option B is an editable 1.20-second recovery")
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		p.set_physics_process(false)
		p.model.set_process(false)
		for variant: StringName in [&"face_down",&"face_up"]:
			for slope: float in [0,20]:
				p.motor.teleport(Transform3D.IDENTITY)
				var normal := Basis(Vector3.FORWARD,deg_to_rad(slope))*Vector3.UP
				var tilt := Basis(Vector3.UP,0.7)*Basis(Vector3.RIGHT,PI/2 if variant == &"face_up" else -PI/2)
				var captured := lying_pose(tilt)
				var chosen: Dictionary = p.reactions.recovery_orientation(captured[p.model.rig.bone(p.model.skeleton,"Body")].basis)
				check(chosen.variant == variant and chosen.facing.dot(Vector3.FORWARD.rotated(Vector3.UP,0.7)) > 0.99,"%s Hz %s: select pose and settled heading independently of old actor facing" % [rate,variant])
				var sampler = p.presentation.get_up
				sampler.begin(captured,variant,p.reactions.definition.get_up_pose,normal)
				sampler.sample(0)
				var handover := world_pose()
				var exact := true
				for bone in captured.size(): exact = exact and handover[bone].origin.distance_to(captured[bone].origin) < 0.0001 and handover[bone].basis.is_equal_approx(captured[bone].basis)
				check(exact,"Ragdoll-to-animation handover preserves every bone's world position")
				var at := p.global_transform
				var last := handover
				var jump := 0.0
				var fastest := ""
				var lowest := INF
				var hand_error := 0.0
				var foot_error := 0.0
				var finite := true
				var count := int(rate*1.2)
				for sample in range(1,count+1):
					var progress := float(sample)/count
					sampler.sample(progress)
					var current := world_pose()
					for bone in current.size():
						if current[bone].origin.distance_to(last[bone].origin) > jump:
							jump = current[bone].origin.distance_to(last[bone].origin)
							fastest = "%s at %.3f" % [p.model.skeleton.get_bone_name(bone),progress]
						finite = finite and current[bone].origin.is_finite()
					last = current
					if progress >= 0.18:
						lowest = minf(lowest,p.model.dodge_skin_min_height(normal))
					var planting := progress >= 0.18 and progress <= 0.30 if variant == &"face_down" else progress >= 0.23 and progress <= 0.32
					if planting:
						hand_error = maxf(hand_error,IK.position(p.model.skeleton,p.model.rig.bone(p.model.skeleton,"Hand.l")).distance_to(sampler.contact_targets["Hand.l"]))
					var foot_start: float = sampler.definition.back_foot_plant_start if variant == &"face_up" else sampler.definition.front_foot_plant_start
					if progress >= foot_start and progress <= sampler.definition.foot_plant_end:
						foot_error = maxf(foot_error,IK.position(p.model.skeleton,p.model.rig.bone(p.model.skeleton,"Foot.l")).distance_to(sampler.contact_targets["Foot.l"]))
				check(finite and p.global_transform == at,"Pose sampling never moves the collision body or produces invalid transforms")
				check(jump < 12.0/rate,"%s Hz %s slope %.0f: continuous bone paths (largest step %.3f m; %s)" % [rate,variant,slope,jump,fastest])
				check(lowest >= -0.025,"Armor stays above its support plane after entry (minimum %.3f m)" % lowest)
				check(hand_error < 0.025 and foot_error < 0.005,"Planted hand/foot retain their anchors (errors %.3f / %.3f m)" % [hand_error,foot_error])
				sampler.reset()
				check(sampler.recovery_pose.is_empty() and sampler.contact_targets.is_empty() and sampler.definition == null,"Reset releases pose snapshots, contacts and definition ownership")
	# Gameplay duration, ownership and interruptions use actual physics/reactions.
	Engine.physics_ticks_per_second = 60
	p.model.set_process(true)
	await prepare(Vector3(0,3,0))
	p.take_damage(5,"get_up_test")
	for frame in 360:
		if p.reactions.getting_up: break
		await settle(1)
	check(p.reactions.getting_up and p.state == p.State.GET_UP,"Actual surviving fall acquires the get-up action")
	var clock: float = p.reactions.get_up_time
	var pose_before := world_pose()
	paused = true
	await settle(5)
	check(p.reactions.get_up_time == clock and world_pose() == pose_before,"Pause freezes recovery clock and supported pose")
	paused = false
	var health: float = p.health
	p.take_damage(5,"surviving_get_up_hit")
	check(p.health == health-5 and p.state == p.State.GET_UP and p.actions.active_definition.id == &"ragdoll","Nonlethal damage remains effective without stealing recovery ownership")
	var request: RefCounted = p.actions.request("jump",true)
	check(request.resolved and not request.accepted and p.actions.buffered.is_empty(),"Get-up remains committed after a surviving hit")
	while p.reactions.getting_up and p.reactions.get_up_time < 1.1: await settle(1)
	check(p.reactions.getting_up,"Control stays committed beyond the old 0.85-second duration")
	for frame in 30:
		if not p.reactions.active: break
		await settle(1)
	check(not p.reactions.active and p.reactions.get_up_time >= 1.2 and p.reactions.get_up_time <= 1.2+1.0/60+0.001,"Recovery releases control at 1.20 s within one physics tick")
	check(p.actions.active_definition == null and p.presentation.get_up.recovery_pose.is_empty(),"Completion releases action and presentation state together")
	Engine.physics_ticks_per_second = original_rate
	stage.queue_free()
	await settle(2)
	print("GET UP: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
