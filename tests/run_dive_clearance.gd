extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var stage: Node3D
var geometry: Node3D
var player: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func tick() -> void:
	await physics_frame
	await process_frame
func clear_geometry() -> void:
	player.set_physics_process(false)
	if is_instance_valid(geometry):
		geometry.queue_free()
		await tick()
	geometry = Node3D.new()
	stage.add_child(geometry)
func place(at: Transform3D) -> void:
	player.reset_for_lab(at)
	player.set_physics_process(true)
	for i in 6: await tick()
func dive() -> Dictionary:
	var start := player.position
	var peak := 0.0
	var arc := 0.0
	var landed := false
	var roll_supported := true
	var immunity_ok := true
	var cost_ok := true
	var requested := 0.0
	var accepted: bool = (await ActionTest.start(player,"dodge"))
	var stamina: float = player.stamina
	cost_ok = accepted and is_equal_approx(stamina,player.tuning.stamina_max-player.tuning.dodge_forward.stamina_cost)
	var limit := Engine.physics_ticks_per_second*3
	for i in limit:
		await tick()
		peak = maxf(peak,player.position.y-start.y)
		if player.forward_dive.active:
			var action = player.forward_dive
			arc = maxf(arc,action.launch_height)
			requested = maxf(requested,action.definition.distance-player.dodge_distance_left)
			cost_ok = cost_ok and player.stamina >= stamina
			if action.since_launch >= 0.32 or action.phase == 0: immunity_ok = immunity_ok and not player.invulnerable
			if action.phase == 2:
				landed = true
				roll_supported = roll_supported and player.is_on_floor()
		else: break
	return {"peak":peak,"arc":arc,"landed":landed,"supported":roll_supported,
		"immunity":immunity_ok,"cost":cost_ok,"requested":requested,"end":player.position}
func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	player = load("res://scenes/player.tscn").instantiate()
	player.combat_enabled = false
	player.controller.manual = true
	stage.add_child(player)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for gap in [0.5,0.6]:
			for setback in [0.05,0.35,0.8,1.4]:
				await clear_geometry()
				var rig = load("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
				rig.gap = gap
				rig.show_labels = false
				geometry.add_child(rig)
				await place(Transform3D(Basis.IDENTITY,Vector3(0,0.62,setback)))
				var result := await dive()
				var label := "%s Hz / %.1f m gap / %.2f m setback" % [rate,gap,setback]
				check(result.landed and player.is_on_floor() and player.position.y > 0.99 and player.position.z < -gap-0.32,label+": lands on 1 m deck from 0.6 m deck (%s)" % player.position)
				check(result.arc > 0.4 and result.arc < 0.53 and result.supported and result.immunity and result.cost and result.requested <= 5.5001,label+": relative arc, real contact, cost and immunity preserved (%.3f)" % result.arc)
		for distance in [0.4,0.8,1.5,2.4]:
			await clear_geometry()
			Shapes.solid(geometry,Vector3(30,0.2,30),Vector3(0,-0.1,0),Color.GRAY)
			Shapes.solid(geometry,Vector3(3,0.6,7),Vector3(0,0.3,-distance-3.5),Color.GRAY)
			await place(Transform3D(Basis.IDENTITY,Vector3(0,0.02,0)))
			var result := await dive()
			check(result.landed and player.position.z < -distance-0.32 and player.position.y > 0.59,"%s Hz / obstacle %.1f m ahead: clears 0.6 m top (%s, arc %.3f)" % [rate,distance,player.position,result.arc])
		# Diagonal approach to a world-aligned obstacle, rather than only rotated rigs.
		await clear_geometry()
		Shapes.solid(geometry,Vector3(30,0.2,30),Vector3(0,-0.1,0),Color.GRAY)
		Shapes.solid(geometry,Vector3(10,0.6,7),Vector3(0,0.3,-4.5),Color.GRAY)
		await place(Transform3D(Basis(Vector3.UP,PI/4),Vector3(0,0.02,0)))
		var diagonal := await dive()
		check(diagonal.arc > 0.6 and player.position.y > 0.59 and player.position.z < -1.4,"%s Hz: diagonal dive crosses world-aligned 0.6 m edge" % rate)
	Engine.physics_ticks_per_second = original_rate
	# All headings, far from world origin: absolute elevation must not affect the rise.
	for index in 8:
		await clear_geometry()
		var heading := float(index)*PI/4
		geometry.transform = Transform3D(Basis(Vector3.UP,heading),Vector3(20,12,20))
		var rig = load("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
		rig.show_labels = false
		geometry.add_child(rig)
		await place(geometry.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,0.62,0.35)))
		var result := await dive()
		var local_end := geometry.to_local(player.global_position)
		check(local_end.y > 0.99 and local_end.z < -0.92 and result.arc < 0.53,"Heading %.0f degrees: raised-gap dive is independent of world origin" % rad_to_deg(heading))
	# Real collision must win over adaptive intent.
	for scenario in ["wall","ceiling","wall_before_landing","behind","narrow"]:
		await clear_geometry()
		Shapes.solid(geometry,Vector3(30,0.2,30),Vector3(0,-0.1,0),Color.GRAY)
		match scenario:
			"wall": Shapes.solid(geometry,Vector3(4,0.7,7),Vector3(0,0.35,-4.5),Color.GRAY)
			"ceiling":
				Shapes.solid(geometry,Vector3(4,0.6,7),Vector3(0,0.3,-4.5),Color.GRAY)
				Shapes.solid(geometry,Vector3(4,0.3,12),Vector3(0,2.35,-3),Color.GRAY)
			"wall_before_landing":
				Shapes.solid(geometry,Vector3(4,4,0.2),Vector3(0,2,-0.8),Color.GRAY)
				Shapes.solid(geometry,Vector3(4,0.6,7),Vector3(0,0.3,-4.7),Color.GRAY)
			"behind": Shapes.solid(geometry,Vector3(4,0.6,1),Vector3(0,0.3,1.8),Color.GRAY)
			"narrow": Shapes.solid(geometry,Vector3(4,0.6,0.35),Vector3(0,0.3,-1.8),Color.GRAY)
		await place(Transform3D(Basis.IDENTITY,Vector3(0,0.02,0)))
		var result := await dive()
		if scenario == "narrow":
			check(result.arc > 0.6 and player.position.z < -3 and player.is_on_floor() and player.position.y < 0.01,"Narrow 0.6 m barrier: crosses and returns to lower ground")
		elif scenario == "behind":
			check(result.arc == 0.25 and absf(player.position.z+5.5) < 0.06,"Obstacle behind player does not raise the forward arc")
		else:
			check(result.arc == 0.25 and player.position.z > -1 and player.position.y < 0.01,"%s: unsuitable landing cannot boost through solid collision" % scenario)
	for scenario in ["long_gap","lower_landing","level_gap"]:
		await clear_geometry()
		var rig = load("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
		rig.gap = 7.0 if scenario == "long_gap" else 0.6
		rig.target_height = 0.2 if scenario == "lower_landing" else 0.6
		rig.show_labels = false
		geometry.add_child(rig)
		Shapes.solid(geometry,Vector3(30,0.2,30),Vector3(0,-10.1,0),Color.GRAY)
		await place(Transform3D(Basis.IDENTITY,Vector3(0,0.62,0.35)))
		var result := await dive()
		if scenario == "long_gap":
			check(result.arc == 0.25 and player.position.y < -9.9 and player.position.z < -7.0,"Unreachable gap keeps forward dive momentum while falling to the catch floor, without a renewed launch")
		else:
			check(result.arc == 0.25 and absf(player.position.y-rig.target_height) < 0.005 and player.position.z < -1,"%s: keeps shallow arc and lands on actual surface" % scenario)
	# The selected launch plan is owned by the action instance and cleared on reset.
	await clear_geometry()
	var rig = load("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
	geometry.add_child(rig)
	Shapes.solid(geometry,Vector3(10,0.2,15),Vector3(12,-0.1,-3),Color.GRAY)
	await place(Transform3D(Basis.IDENTITY,Vector3(0,0.62,0.35)))
	var second = load("res://scenes/player.tscn").instantiate()
	second.combat_enabled = false
	second.controller.manual = true
	stage.add_child(second)
	second.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(12,0.02,0)))
	for i in 6: await tick()
	(await ActionTest.start(player,"dodge"))
	(await ActionTest.start(second,"dodge"))
	for i in 12: await tick()
	check(player.forward_dive.launch_height > 0.5 and second.forward_dive.launch_height == 0.25 and player.tuning.dodge_forward == second.tuning.dodge_forward and player.tuning.dodge_forward.height == 0.25,"Two characters share an unchanged definition and choose independent launch arcs")
	player.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.62,0.35)))
	check(not player.forward_dive.active and player.forward_dive.launch_height == 0 and player.forward_dive.clearance_rise == 0 and player.actions.active_definition == null,"Reset releases the adaptive plan and action ownership")
	second.queue_free()
	stage.queue_free()
	await tick()
	print("DIVE CLEARANCE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
