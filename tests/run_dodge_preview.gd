extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)
func tick() -> void:
	await physics_frame
	await process_frame
func ready_replay(preview: Node) -> void:
	preview.restart()
	for i in 5:
		await tick()
		if not preview.waiting_for_floor: break

func run() -> void:
	var preview = load("res://scenes/dodge_preview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	check(preview.body.get_script() == preload("res://features/character/player.gd"),"Preview instantiates the playable player")
	check(preview.body.motor != null and preview.body.actions != null,"Preview uses the shared motor and action controller")
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		await ready_replay(preview)
		var apex := 0.0
		var lowest := INF
		var grounded_roll := true
		var nonnegative := true
		var seen_air := false
		var planted := 0.0
		for frame in int(rate*1.4):
			await tick()
			apex = maxf(apex,preview.body.position.y)
			lowest = minf(lowest,preview.body.position.y+preview.knight.dodge_skin_min_height())
			nonnegative = nonnegative and preview.remaining >= 0
			if preview.phase == preview.Phase.DIVE: seen_air = true
			if preview.phase == preview.Phase.ROLL: grounded_roll = grounded_roll and preview.body.is_on_floor()
			if preview.phase == preview.Phase.PUSH_OFF and preview.pose != null:
				for side in ["l","r"]:
					var bone: int = preview.knight.rig.bone(preview.pose.skeleton,"Foot."+side)
					var actual: Vector3 = preview.knight.locomotion.world_position(preview.pose.skeleton,bone)
					planted = maxf(planted,actual.distance_to(preview.pose.feet[side]))
			if preview.phase == preview.Phase.FINISHED: break
		check(absf(apex-0.25) < 0.008,"%s Hz: same 0.25 m physical arc (%.4f)" % [rate,apex])
		check(grounded_roll and seen_air and preview.landing_time >= preview.push_duration,"%s Hz: roll requires actual contact" % rate)
		check(absf(preview.elapsed-preview.landing_time-0.55) <= 1.0/rate+0.001,"%s Hz: 0.55 s grounded finish within one tick" % rate)
		check(absf(-preview.body.position.z-5.5) < 0.02,"%s Hz: same 5.5 m travel (%.4f)" % [rate,-preview.body.position.z])
		check(lowest >= 0.005,"%s Hz: armor above floor (%.4f)" % [rate,lowest])
		check(planted < 0.04,"%s Hz: preparation feet planted (%.4f)" % [rate,planted])
		check(nonnegative and preview.phase == preview.Phase.FINISHED,"%s Hz: finite budget and recovery" % rate)
		check(preview.body.actions.active_definition == null and preview.pose == null,"%s Hz: finish releases animation and action ownership" % rate)
	Engine.physics_ticks_per_second = 60
	await ready_replay(preview)
	preview.toggle_pause()
	var old_position: Vector3 = preview.body.position
	var old_time: float = preview.elapsed
	var old_pose: Array = preview.pose.snapshot()
	for i in 5: await tick()
	check(preview.body.position == old_position and preview.elapsed == old_time and preview.pose.snapshot() == old_pose,"Pause freezes body and pose")
	preview.step_frame()
	await tick()
	check(absf(preview.elapsed-old_time-1.0/60.0) < 0.00001 and not preview.playing,"Frame step advances one real physics tick")
	await ready_replay(preview)
	preview.playback_speed = 0.25
	var before: float = preview.elapsed
	for i in 12: await tick()
	check(absf(preview.elapsed-before-0.05) < 0.005,"Quarter speed scales the actual simulation")
	preview.playback_speed = 1.0
	for cycle in 3:
		preview.restart()
		check(preview.body.position == Vector3.ZERO and preview.elapsed == 0 and preview.remaining == preview.travel_distance and preview.landing_time == -1,"Replay %s resets character and review state" % cycle)
		for i in 80:
			await tick()
			if preview.phase == preview.Phase.FINISHED: break
		check(preview.phase == preview.Phase.FINISHED and absf(-preview.body.position.z-5.5) < 0.02,"Replay %s repeats shared ability" % cycle)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/arena.tscn","F5 still launches the courtyard")
	preview.queue_free()
	await tick()
	check(Engine.time_scale == 1.0,"Unloading preview restores playback time scale")
	print("DODGE PREVIEW: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
