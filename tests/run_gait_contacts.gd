extends SceneTree
## Source fidelity and contact behavior, independent of gameplay movement speeds.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(30,1,30),Vector3(0,-0.5,0),Color.GRAY)
	var source: Node3D = load("res://assets/third_party/quaternius/UAL1_Standard.glb").instantiate()
	world.add_child(source)
	var source_skeleton: Skeleton3D = source.find_child("Skeleton3D",true,false)
	var source_player: AnimationPlayer = source.find_child("AnimationPlayer",true,false)
	source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for scene in ["psx_knight","ual_mannequin"]:
		var actor = load("res://scenes/player.tscn").instantiate()
		actor.model_scene = load("res://scenes/models/"+scene+".tscn")
		actor.controller.manual = true
		world.add_child(actor)
		for i in 8: await physics_frame
		actor.set_physics_process(false)
		var model = actor.model
		model.set_process(false)
		var s: Skeleton3D = model.skeleton
		var a: AnimationPlayer = model.animation
		for name in ["jog","sprint"]:
			var clip := a.get_animation("running/"+name)
			var source_name := "Jog_Fwd" if name == "jog" else "Sprint"
			check(clip.get_meta("source_clip","") == source_name,scene+": uses UAL "+source_name)
			check(is_equal_approx(clip.length,source_player.get_animation(source_name).length),"Preserve source duration")
			check(float(clip.get_meta("reference_speed",0.0)) > 4.5,"Measured cadence, not gameplay top speed")
			var source_offset_min := INF
			var source_offset_max := -INF
			var max_swing_shift := 0.0
			var max_angle := 0.0
			var swings := 0
			var low := INF
			for hz in [30,60,120]:
				model.locomotion.reset()
				for frame in hz:
					var time: float = frame*clip.length/hz
					a.play("running/"+name)
					a.seek(time,true)
					a.advance(0)
					s.force_update_all_bone_transforms()
					var before := {}
					for side in ["l","r"]:
						before[side] = s.global_transform*s.get_bone_global_pose(model.rig.bone(s,"Foot."+side))
					if scene == "ual_mannequin":
						source_player.play(source_name)
						source_player.seek(time,true)
						source_player.advance(0)
						var source_y := source_skeleton.get_bone_global_pose(source_skeleton.find_bone("pelvis")).origin.y
						var offset := s.get_bone_global_pose(s.find_bone("pelvis")).origin.y-source_y
						source_offset_min = minf(source_offset_min,offset)
						source_offset_max = maxf(source_offset_max,offset)
					var plants: Dictionary = model.locomotion.clip_contacts(clip,time)
					model.locomotion.update(1.0/hz,actor,s,plants)
					for side in ["l","r"]:
						var after := s.global_transform*s.get_bone_global_pose(model.rig.bone(s,"Foot."+side))
						var original: Transform3D = before[side]
						max_angle = maxf(max_angle,after.basis.orthonormalized().get_rotation_quaternion().angle_to(original.basis.orthonormalized().get_rotation_quaternion()))
						if plants[side] == 0.0:
							swings += 1
							max_swing_shift = maxf(max_swing_shift,after.origin.distance_to(original.origin))
							check(not model.locomotion.anchors.has(side),"Swing foot has no ground lock")
					low = minf(low,model.dodge_skin_min_height())
			check(swings > 0,"Cycle includes foot release")
			check(max_swing_shift < 0.025,"Swing pose retained: %.4f m" % max_swing_shift)
			check(max_angle < 0.002,"IK preserves ankle orientation: %.4f radians" % max_angle)
			check(low > -0.04,"Foot clearance: %.4f m" % low)
			if scene == "ual_mannequin":
				check(source_offset_max-source_offset_min < 0.001,"Preserve authored pelvis bounce: offset variation %.5f" % (source_offset_max-source_offset_min))
		actor.free()
	print("GAIT CONTACTS RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
