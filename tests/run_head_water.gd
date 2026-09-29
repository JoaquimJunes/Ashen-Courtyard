extends SceneTree
const Detector = preload("res://features/swimming/head_water_detector.gd")
const Water = preload("res://features/swimming/water_volume.tscn")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)
func wet_time(intervals: Array) -> float:
	var seconds := 0.0
	for interval in intervals:
		if interval.submerged: seconds += interval.seconds
	return seconds
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var water: Area3D = Water.instantiate()
	water.size = Vector3(2,4,2)
	water.show_surface = false
	world.add_child(water)
	var sensor := Detector.new()
	sensor.configure(world)
	var changes: Array[bool] = []
	sensor.head_submerged_changed.connect(func(value): changes.append(value))
	for rate in [30,60,120]:
		var dt: float = 1.0/rate
		sensor.reset()
		check(wet_time(sensor.sample(Vector3(0,0.1,0),dt)) == 0 and not sensor.head_submerged,"%s: head in air does not drain" % rate)
		sensor.sample(Vector3(0,-0.03,0),dt)
		check(sensor.head_submerged,"%s: mouth enters below 2 cm" % rate)
		sensor.sample(Vector3(0,0.01,0),dt)
		check(sensor.head_submerged,"%s: small surface bob retains submerged state" % rate)
		sensor.sample(Vector3(0,0.03,0),dt)
		check(not sensor.head_submerged,"%s: mouth above 2 cm regains air" % rate)
		sensor.reset()
		sensor.sample(Vector3(0,0.2,0),dt)
		var submerged := 0.0
		for i in rate: submerged += wet_time(sensor.sample(Vector3(0,0.2-0.4*(i+1)/rate,0),dt))
		check(absf(submerged-0.45) < 0.00001,"%s: exact fractional entry time independent of tick rate" % rate)
		sensor.reset()
		sensor.sample(Vector3(-2,-0.2,0),dt)
		var before_changes := changes.size()
		check(absf(wet_time(sensor.sample(Vector3(2,-0.2,0),1.0))-0.5) < 0.00001 and not sensor.head_submerged,"%s: full water crossing between dry endpoints counts immersion" % rate)
		check(changes.size() == before_changes+2,"%s: brief crossing publishes both head-state transitions" % rate)
		sensor.reset()
		check(wet_time(sensor.sample(Vector3(0,-0.2,0),dt)) == dt,"%s: reset seeds new position without sweeping across teleport" % rate)
	check(changes.has(true) and changes.has(false),"Head state changes are observable")
	water.position.y = 1.1
	var p: CharacterBody3D = preload("res://scenes/player.tscn").instantiate()
	world.add_child(p)
	p.set_physics_process(false)
	p.model.set_process(false)
	p.hitboxes.capture()
	p.swimming.tick_breath(0.1)
	check(not p.swimming.head_detector.head_submerged and p.resources.breath == 20,"Standing head above wading water keeps breath")
	p.model.animation.play("crouch/crouch_idle")
	p.model.animation.seek(0.4,true)
	p.model.animation.advance(0)
	p.hitboxes.capture()
	p.swimming.tick_breath(0.2)
	check(p.swimming.head_detector.head_submerged and not p.swimming.active and p.resources.breath < 20,"Visible crouched mouth drains without swimming movement mode")
	var head: int = p.model.skeleton.find_bone("Head")
	var mouth: Vector3 = p.model.skeleton.global_transform*p.model.skeleton.get_bone_global_pose(head)*p.hitboxes.profile.breathing_offset
	check(p.swimming.head_detector.breathing_position.is_equal_approx(mouth),"Detector follows visible mouth/nose marker")
	p.camera.global_position.y = 8
	p.get_node("SwimmingHUD")._process(0)
	check(not p.get_node("SwimmingHUD").camera_submerged and p.swimming.head_detector.head_submerged,"Dry camera does not give the character air")
	# Put a thin volume around only the head: mode, torso and camera stay dry.
	for rate in [30,60,120]:
		var dt: float = 1.0/rate
		p.reset_resources()
		p.swimming.reset()
		p.combat_enabled = false
		p.invulnerable = true
		water.size.y = 0.2
		water.position.y = mouth.y+0.05
		for i in 20*rate: p.swimming.tick_breath(dt)
		check(p.resources.breath < 0.00001 and p.health == 100,"%s: head-only immersion consumes twenty seconds of breath" % rate)
		for i in rate: p.swimming.tick_breath(dt)
		check(p.health == 90 and not p.reactions.active,"%s: head-only drowning uses shared damage without stagger or lab-combat dependence" % rate)
		water.position.y = mouth.y-0.1
		for i in 3*rate: p.swimming.tick_breath(dt)
		check(is_equal_approx(p.resources.breath,20) and not p.swimming.head_detector.head_submerged,"%s: mouth in air refills in three seconds" % rate)
	water.position.y = mouth.y+0.05
	p.swimming.tick_breath(0.2)
	water.queue_free()
	await process_frame
	var breath: float = p.resources.breath
	p.swimming.tick_breath(0.1)
	check(not p.swimming.head_detector.head_submerged and p.resources.breath > breath,"Removed water cannot leave stale immersion")
	p.swimming.head_detector.sample(Vector3.ZERO,0.1)
	p.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	check(not p.swimming.head_detector.has_previous and p.resources.breath == 20,"Teleport clears head history and restores breath")
	var other := Detector.new()
	other.configure(world)
	check(not other.has_previous and other != p.swimming.head_detector,"Detector state belongs to each character")
	var callback_sensor := Detector.new()
	callback_sensor.configure(world)
	var replacement: Area3D = Water.instantiate()
	replacement.show_surface = false
	world.add_child(replacement)
	var reset_callback := func(wet):
		if wet: callback_sensor.reset()
	callback_sensor.head_submerged_changed.connect(reset_callback)
	check(callback_sensor.sample(Vector3(0,-0.2,0),0.1).is_empty() and not callback_sensor.has_previous,"Reentrant reset discards the old sample intervals")
	callback_sensor.head_submerged_changed.disconnect(reset_callback)
	p.reactions.begin(false,true)
	p.hitboxes.capture()
	replacement.global_position = p.hitboxes.breathing_position()+Vector3.UP*0.05
	replacement.size = Vector3(2,0.2,2)
	p.resources.breath = 0
	p.resources.health = 10
	p.swimming.drowning_clock = 0
	p.swimming.head_detector.reset()
	p.swimming.tick_breath(1.1)
	check(p.dead and p.reactions.active and p.reactions.lethal,"Drowning an existing ragdoll commits death without allowing a corpse get-up")
	world.queue_free()
	await process_frame
	check(not is_instance_valid(p),"Scene unload releases character")
	print("HEAD WATER: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
