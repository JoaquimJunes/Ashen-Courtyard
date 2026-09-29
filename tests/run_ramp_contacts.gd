extends SceneTree
## Sustained 30-degree stance contact, including uphill/downhill and both rigs.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func tick(actor: CharacterBody3D, delta: float) -> void:
	await physics_frame
	actor._physics_process(delta)
	actor.pose_driver.evaluate(delta)
	await process_frame
func joint_speeds(actor: CharacterBody3D, previous: Dictionary, delta: float) -> Vector2:
	var peak := Vector2.ZERO
	for role in ["LowerLeg.l","LowerLeg.r","Foot.l","Foot.r"]:
		var skeleton: Skeleton3D = actor.model.skeleton
		var position: Vector3 = actor.model.locomotion.world_position(skeleton,actor.model.rig.bone(skeleton,role))-actor.global_position
		if previous.has(role):
			var speed: float = position.distance_to(previous[role])/delta
			if role.begins_with("Foot"): peak.x = maxf(peak.x,speed)
			else: peak.y = maxf(peak.y,speed)
		previous[role] = position
	return peak
func source_posture_difference(actor: CharacterBody3D, reference: Node3D) -> Vector4:
	# Compare against the same unmodified clip/phase, not an arbitrary world
	# height: the animation's own running bob and posture must remain visible.
	var animation: AnimationPlayer = actor.model.animation
	reference.skeleton.reset_bone_poses()
	reference.animation.play(animation.assigned_animation)
	reference.animation.seek(animation.current_animation_position,true)
	reference.animation.advance(0)
	var actual: Array[Vector3] = []
	var authored: Array[Vector3] = []
	for role in ["Body","Torso","Head"]:
		actual.append(actor.global_basis.inverse()*(actor.model.locomotion.world_position(actor.model.skeleton,actor.model.rig.bone(actor.model.skeleton,role))-actor.global_position))
		authored.append(reference.locomotion.world_position(reference.skeleton,reference.rig.bone(reference.skeleton,role))-reference.global_position)
	var angle := rad_to_deg((actual[2]-actual[0]).angle_to(authored[2]-authored[0]))
	return Vector4(absf(actual[0].y-authored[0].y),absf(actual[1].y-authored[1].y),absf(actual[2].y-authored[2].y),angle)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var ramp = Shapes.solid(world,Vector3(12,0.5,40),Vector3(0,10,0),Color.GRAY)
	ramp.rotation.x = deg_to_rad(30)
	var original_rate := Engine.physics_ticks_per_second
	for model in ["psx_knight","ual_mannequin"]:
		var actor = load("res://scenes/player.tscn").instantiate()
		actor.model_scene = load("res://scenes/models/"+model+".tscn")
		actor.controller.manual = true
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.model.set_process(false)
		var reference: Node3D = load("res://scenes/models/"+model+".tscn").instantiate()
		world.add_child(reference)
		reference.set_process(false)
		reference.position = Vector3(40,0,0)
		for hz in [30,60,120]:
			Engine.physics_ticks_per_second = hz
			var delta: float = 1.0/hz
			for gait in ["jog","sprint","crouch"]:
				if gait == "crouch" and model == "psx_knight": continue # Legacy crouch has no terrain driver.
				for downhill in [false,true]:
					actor.controller.intent.movement = Vector3.ZERO
					actor.controller.intent.sprint = gait == "sprint"
					var z := -5.0 if downhill else 12.0
					var y := 10.0+0.25/cos(deg_to_rad(30))-z*tan(deg_to_rad(30))
					actor.reset_for_lab(Transform3D(Basis(Vector3.UP,PI if downhill else 0),Vector3(0,y+0.05,z)))
					for i in 15: await tick(actor,delta)
					if gait == "crouch":
						check(actor.posture.toggle() == &"","Prepare crouch slope fixture")
						for i in int(hz*0.3)+1: await tick(actor,delta)
					actor.controller.intent.movement = Vector3.BACK if downhill else Vector3.FORWARD
					var samples := 0
					var missing := 0
					var max_gap := 0.0
					var max_error := 0.0
					var minimum := INF
					var finite := true
					var previous_pose := {}
					var peak_knee_speed := 0.0
					var peak_ankle_speed := 0.0
					var posture_error := Vector4.ZERO
					var posture_samples := 0
					for frame in int(hz*2):
						await tick(actor,delta)
						var animation: AnimationPlayer = actor.model.animation
						if not (animation.current_animation.begins_with("running/") or animation.current_animation == "crouch/crouch_walk"):
							previous_pose.clear()
							continue
						# Measure actual posed joints, including swing phases that old stance-only
						# checks missed. Frame-rate-scaled limits reject discontinuous IK flips.
						var speeds := joint_speeds(actor,previous_pose,delta)
						peak_ankle_speed = maxf(peak_ankle_speed,speeds.x)
						peak_knee_speed = maxf(peak_knee_speed,speeds.y)
						if frame > hz/2:
							var difference := source_posture_difference(actor,reference)
							for component in 4: posture_error[component] = maxf(posture_error[component],difference[component])
							posture_samples += 1
						var weights: Dictionary = actor.model.locomotion.clip_contacts(animation.get_animation(animation.current_animation),animation.current_animation_position)
						for side in ["l","r"]:
							if float(weights.get(side,0.0)) < 0.8: continue
							samples += 1
							if not actor.model.locomotion.contacts.has(side):
								missing += 1
								continue
							var contact: Dictionary = actor.model.locomotion.contacts[side]
							max_error = maxf(max_error,contact.ankle.distance_to(contact.target))
							var skeleton: Skeleton3D = actor.model.skeleton
							var transform := skeleton.global_transform*skeleton.get_bone_global_pose(actor.model.rig.bone(skeleton,"Foot."+side))
							finite = finite and transform.is_finite()
							var low := INF
							for point in actor.model.locomotion.sole_points[side]: low = minf(low,actor.get_floor_normal().dot(transform*point-contact.surface))
							minimum = minf(minimum,low)
							max_gap = maxf(max_gap,low)
					actor.controller.intent.movement = Vector3.ZERO
					for frame in int(hz*0.6):
						await tick(actor,delta)
						var speeds := joint_speeds(actor,previous_pose,delta)
						peak_ankle_speed = maxf(peak_ankle_speed,speeds.x)
						peak_knee_speed = maxf(peak_knee_speed,speeds.y)
					var label := "%s %s Hz %s %s" % [model,hz,gait,"down" if downhill else "up"]
					check(samples >= 12 and missing == 0,label+": sustained stance detection (%s samples, %s missing)" % [samples,missing])
					check(max_gap < 0.06,label+": sole gap %.4f m" % max_gap)
					check(max_error < 0.065,label+": target reach error %.4f m" % max_error)
					check(minimum > -0.04 and finite,label+": finite pose / penetration %.4f m" % minimum)
					if gait != "crouch":
						check(peak_knee_speed < minf(16.0,0.35/delta),label+": continuous knee trajectory %.3f m/s" % peak_knee_speed)
						check(peak_ankle_speed < minf(16.0,0.35/delta),label+": continuous ankle trajectory %.3f m/s" % peak_ankle_speed)
					if gait == "crouch":
						# Low-tunnel fitting intentionally lowers the body; ordinary running
						# keeps the previous source-height contract. Feet stay on the slope.
						check(posture_samples >= hz and absf(posture_error.x-posture_error.y) < 0.001 and absf(posture_error.x-posture_error.z) < 0.001,label+": clearance lowers pelvis, torso and head together")
						check(-actor.model.dodge_skin_min_height(Vector3.DOWN) <= actor.posture.definition.crouch_height+0.001,label+": stopped silhouette fits 0.96m clearance on the slope")
					else:
						check(posture_samples >= hz and posture_error.x < 0.09,label+": authored pelvis height preserved (%.3f m maximum difference)" % posture_error.x)
						check(posture_error.y < 0.12 and posture_error.z < 0.15,label+": authored torso/head height preserved (%.3f / %.3f m)" % [posture_error.y,posture_error.z])
					check(posture_error.w < 20.0,label+": modest added body lean (%.2f degrees)" % posture_error.w)
					check(actor.model.locomotion.pelvis_lowering <= actor.model.locomotion.tuning.max_pelvis_lowering,label+": bounded visual adjustment")
					actor.reset_for_lab(Transform3D.IDENTITY)
					check(is_zero_approx(actor.model.locomotion.pelvis_lowering) and actor.model.locomotion.contact_blend_from.is_empty() and actor.model.locomotion.transition_targets.is_empty(),label+": reset clears pelvis and transition correction")
		actor.free()
		reference.free()
	Engine.physics_ticks_per_second = original_rate
	print("RAMP CONTACTS RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
