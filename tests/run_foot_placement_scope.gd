extends "res://tests/run_ual_native_animation.gd"
## Terrain foot placement belongs only to grounded walking/running poses.
var reference_player: AnimationPlayer
var reference_skeleton: Skeleton3D

func contacts_cleared(actor: CharacterBody3D) -> bool:
	var locomotion: RefCounted = actor.model.locomotion
	return locomotion.contacts.is_empty() and locomotion.anchors.is_empty() and locomotion.previous_plants.is_empty() and locomotion.contact_blend_from.is_empty() and locomotion.transition_targets.is_empty() and is_zero_approx(locomotion.pelvis_lowering)

func source_leg_error(actor: CharacterBody3D) -> Vector2:
	# A separate player samples the unchanged library without any terrain solver.
	var animation: AnimationPlayer = actor.model.animation
	reference_skeleton.reset_bone_poses()
	reference_player.play(animation.assigned_animation,0)
	reference_player.seek(animation.current_animation_position,true)
	reference_player.advance(0)
	var error := Vector2.ZERO
	for name in ["pelvis","thigh_l","calf_l","foot_l","thigh_r","calf_r","foot_r"]:
		var bone := reference_skeleton.find_bone(name)
		error.x = maxf(error.x,reference_skeleton.get_bone_pose_rotation(bone).angle_to(actor.model.skeleton.get_bone_pose_rotation(bone)))
		error.y = maxf(error.y,reference_skeleton.get_bone_pose_position(bone).distance_to(actor.model.skeleton.get_bone_pose_position(bone)))
	return error

func begin_walk(rate: int, gait: String = "jog") -> void:
	var actor: CharacterBody3D = actors[0]
	var z := 12.0
	var y := 10.0+0.25/cos(deg_to_rad(30))-z*tan(deg_to_rad(30))
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,y+0.05,z)))
	actor.model.set_process(false)
	actor.model.equipment.set_layout(&"sword")
	intents.clear()
	intents.append(Intent.new())
	actor.submit_intent(intents[0])
	await step(maxi(6,rate/4),rate)
	if gait == "crouch": check(await ActionTest.start(actor,&"crouch"),"Scope fixture enters crouch")
	intents[0].movement = Vector3.FORWARD
	intents[0].sprint = gait == "sprint"
	for frame in rate*2:
		await step(1,rate)
		if frame >= rate/2 and not actor.model.locomotion.anchors.is_empty() and not actor.model.locomotion.contacts.is_empty(): break
	var clip := "crouch/crouch_walk" if gait == "crouch" else "running/"+gait
	check(actor.is_on_floor() and actor.get_floor_normal().y < 0.9 and actor.model.animation.current_animation == clip,"%s Hz: %s fixture walks on the 30-degree slope" % [rate,gait])
	check(not actor.model.locomotion.anchors.is_empty() and not actor.model.locomotion.contacts.is_empty(),"%s Hz: %s retains actual foot placement" % [rate,gait])
	if gait != "crouch":
		var locomotion: RefCounted = actor.model.locomotion
		check(locomotion.pelvis_lowering >= 0.0 and locomotion.pelvis_lowering <= locomotion.tuning.max_pelvis_lowering,"%s Hz: %s keeps terrain pelvis adjustment bounded" % [rate,gait])
		# Ordinary ramps now preserve body height. Seed a permitted residual so
		# the following stop/action still proves both state and visible pose clear.
		var seeded_lowering := minf(0.04,locomotion.tuning.max_pelvis_lowering)
		locomotion.rig.offset_world(actor.model.skeleton,actor.model.rig.bone(actor.model.skeleton,"Body"),Vector3.DOWN*(seeded_lowering-locomotion.pelvis_lowering))
		locomotion.pelvis_lowering = seeded_lowering
		actor.model.skeleton.force_update_all_bone_transforms()

func check_source_legs(actor: CharacterBody3D, label: String, filtered: bool = false) -> void:
	var error := source_leg_error(actor)
	if actor.posture.crouched:
		# Clearance fitting bends the legs, but idle must keep the authored ankle
		# contacts/orientation and must not recreate terrain locks on the slope.
		var matched := true
		for name in ["foot_l","foot_r"]:
			var bone := reference_skeleton.find_bone(name)
			var reference := reference_skeleton.get_bone_global_pose(bone)
			var displayed: Transform3D = actor.model.skeleton.get_bone_global_pose(bone)
			matched = matched and reference.origin.distance_to(displayed.origin) < 0.002 and reference.basis.is_equal_approx(displayed.basis)
		check(matched and -actor.model.dodge_skin_min_height(Vector3.DOWN) <= actor.posture.definition.crouch_height,label+": clearance fitting preserves authored ankle contacts beneath 0.96m")
		return
	# Standing idle intentionally filters source breathing by 45 ms.
	var rotation_limit := deg_to_rad(2.0) if filtered else 0.001
	var position_limit := 0.005 if filtered else 0.00001
	check(error.x < rotation_limit and error.y < position_limit,label+": source pelvis/legs remain unchanged by terrain IK (%.3f degrees, %.4f m)" % [rad_to_deg(error.x),error.y])

func verify_stops(rate: int) -> void:
	var actor: CharacterBody3D = actors[0]
	for gait in ["jog","sprint","crouch"]:
		await begin_walk(rate,gait)
		intents[0].movement = Vector3.ZERO
		intents[0].sprint = false
		await step(rate,rate)
		var label := "%s Hz: stopped %s" % [rate,gait]
		check(contacts_cleared(actor),label+" clears foot anchors, contacts and pelvis correction")
		check_source_legs(actor,label,gait != "crouch")
		if gait == "jog":
			actor.model.equipment.set_layout(&"all_stowed")
			await step(rate,rate)
			check(contacts_cleared(actor),"Unarmed idle also leaves foot placement disabled")
			check_source_legs(actor,"Unarmed idle",true)

func verify_actions(rate: int) -> void:
	var actor: CharacterBody3D = actors[0]
	for action in ["light","heavy","cast","heal"]:
		await begin_walk(rate)
		intents[0].movement = Vector3.ZERO
		actor.velocity = Vector3.ZERO
		if action == "heal": actor.health -= 10
		var ticket: RefCounted = actor.actions.request(action)
		actor.actions.tick()
		check(ticket.accepted,"%s Hz: scope fixture accepts %s" % [rate,action])
		actor.actions.timer = actor.actions.active_definition.windup
		actor.presentation.prepare()
		# Deliberate source-landmark preview outside the automatic physics tick.
		actor.model.update_pose(1.0/rate)
		var label := "%s Hz: %s" % [rate,action]
		check(contacts_cleared(actor),label+" cannot retain or recreate walking foot placement")
		check_source_legs(actor,label)

func verify_lifecycle(rate: int) -> void:
	var actor: CharacterBody3D = actors[0]
	for event in ["jump","death","ragdoll","reset"]:
		await begin_walk(rate)
		intents[0].movement = Vector3.ZERO
		match event:
			"jump":
				check(await ActionTest.start(actor,&"jump"),"Scope fixture starts a jump")
				await step(maxi(3,rate/5),rate)
				check(not actor.is_on_floor(),"Scope fixture is airborne")
			"death":
				actor.take_damage(actor.health+1,"scope_death_%s" % rate)
				check(actor.dead,"Scope fixture enters death")
			"ragdoll":
				actor.reactions.begin(false,true)
				check(actor.reactions.active,"Scope fixture hands the pose to ragdoll")
			"reset":
				var airborne := actor.global_transform
				airborne.origin.y += 1.0
				actor.reset_for_lab(airborne)
				check(not actor.motor.last_result.grounded and actor.model.animation.assigned_animation == "k_idle","%s Hz: airborne reset cannot inherit cached ground contact and sword stance" % rate)
		check(contacts_cleared(actor),"%s Hz: %s clears previous walking foot placement" % [rate,event])

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var ramp := Shapes.solid(world,Vector3(12,0.5,40),Vector3(0,10,0),Color.GRAY)
	ramp.rotation.x = deg_to_rad(30)
	var actor: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	var combat := preload("res://features/combat/combat_services.gd").new()
	combat.host = world
	world.add_child(combat)
	actor.services = combat
	actor.controller.manual = true
	world.add_child(actor)
	actor.model.set_process(false)
	actors.append(actor)
	var reference: Node3D = preload("res://tools/ual_animation_build_manifest.tres").source_scene.instantiate()
	world.add_child(reference)
	reference_player = reference.find_child("AnimationPlayer",true,false)
	reference_skeleton = reference.find_child("Skeleton3D",true,false)
	reference_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(PROFILE.install(reference_player),"Unmodified reference clips install for pose comparison")
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await verify_stops(rate)
		await verify_actions(rate)
		await verify_lifecycle(rate)
	Engine.physics_ticks_per_second = original_rate
	world.free()
	actors.clear()
	print("FOOT PLACEMENT SCOPE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
