extends Node3D
## Exportable, opt-in benchmark using production characters and existing action APIs.
## Run its scene with -- --quick, or the default 1/5/10/15 × five-scenario matrix.
const Intent = preload("res://features/character/character_intent.gd")
var counts: Array[int] = [1,5,10,15]
var scenarios: Array[String] = ["idle","slope","crouch","combat","recovery"]
var warmup_seconds := 3.0
var measurement_seconds := 5.0
var output := "user://animation-benchmark.json"
var actors: Array[CharacterBody3D] = []
var intent: Array[RefCounted] = []
var scene: PackedScene
var world: Node3D
var services: Node
var camera: Camera3D
var label: Label
var cases: Array[Dictionary] = []
var results: Array[Dictionary] = []
var current_case := -1
var started_us := 0
var previous_frame_us := 0
var measured := false
var changing := true
var physics_frame := -1
var physics_count := 0
var physics_total_us := 0
var frames := PackedFloat64Array()
var physics_cpu := PackedFloat64Array()
var render_cpu := PackedFloat64Array()
var start_memory := {}
var spawn_stats := {}
var actions_started := 0
var recovery_count := 0
var next_actions: Array[float] = []
var alternation: Array[int] = []
var startup_ms := 0.0
var trace_spikes := false
var slow_frames: Array[Dictionary] = []
var omitted_slow_frames := 0
var frame_pose_us := 0
var frame_physics_ticks := 0
var frame_actions := 0

func _ready() -> void:
	startup_ms = Time.get_ticks_usec()/1000.0
	process_priority = 200 # Observe completed model render callbacks.
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		DisplayServer.window_set_size(Vector2i(1280,720))
	get_tree().root.content_scale_size = Vector2i(1280,720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioServer.set_bus_mute(0,true)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--trace-spikes": trace_spikes = true
		elif argument == "--quick":
			counts.assign([1])
			warmup_seconds = 0.25
			measurement_seconds = 0.5
		elif argument.begins_with("--warmup="): warmup_seconds = maxf(0.05,argument.get_slice("=",1).to_float())
		elif argument.begins_with("--measure="): measurement_seconds = maxf(0.05,argument.get_slice("=",1).to_float())
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--counts="):
			counts.clear()
			for value in argument.get_slice("=",1).split(","):
				if value.to_int() > 0 and value.to_int() <= 64: counts.append(value.to_int())
		elif argument.begins_with("--scenarios="):
			var requested := argument.get_slice("=",1).split(",")
			scenarios.clear()
			for value in requested:
				if value in ["idle","slope","crouch","combat","recovery"]: scenarios.append(value)
	if counts.is_empty() or scenarios.is_empty():
		push_error("Benchmark requires a supported count and scenario.")
		get_tree().quit(1)
		return
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("17212b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a6b4c0")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 29
	camera.position = Vector3(16,24,28)
	add_child(camera)
	camera.look_at(Vector3(0,2,0))
	camera.current = true
	var ui := CanvasLayer.new()
	add_child(ui)
	label = Label.new()
	label.position = Vector2(20,18)
	label.add_theme_font_size_override("font_size",22)
	ui.add_child(label)
	for count in counts:
		for scenario in scenarios: cases.append({"characters":count,"scenario":scenario})
	bootstrap.call_deferred()

func rss() -> Dictionary:
	var result := {"rss_mib":0.0,"process_peak_rss_mib":0.0}
	var file := FileAccess.open("/proc/self/status",FileAccess.READ)
	if file == null: return result
	# procfs reports length zero; reading by reported file length loses its contents.
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmRSS:"): result.rss_mib = line.trim_prefix("VmRSS:").strip_edges().get_slice(" ",0).to_float()/1024.0
		elif line.begins_with("VmHWM:"): result.process_peak_rss_mib = line.trim_prefix("VmHWM:").strip_edges().get_slice(" ",0).to_float()/1024.0
	return result

func bootstrap() -> void:
	var load_start := Time.get_ticks_usec()
	scene = load("res://scenes/player.tscn")
	spawn_stats.resource_load_ms = (Time.get_ticks_usec()-load_start)/1000.0
	world = Node3D.new()
	add_child(world)
	services = get_node("/root/GameSession").configure_world(world)
	for index in 2:
		var before := Time.get_ticks_usec()
		var actor := spawn(Vector3(index*5,0,0),index)
		spawn_stats["first_instance_ms" if index == 0 else "warm_instance_ms"] = (Time.get_ticks_usec()-before)/1000.0
		actor.free()
	spawn_stats.note = "First and second benchmark instance construction; GameSession preloads player resources and the release launch flag passes through normal startup, so these are warm resource/instance measurements, not cold disk-load claims."
	world.free()
	world = null
	await next_case()

func spawn(at: Vector3, index: int) -> CharacterBody3D:
	var actor: CharacterBody3D = scene.instantiate()
	actor.services = services
	actor.controller.manual = true
	actor.position = at
	world.add_child(actor)
	# Every measured body keeps production actions, motor, skin, attachments and IK.
	# Only per-player camera/HUD processing is unnecessary for this shared view.
	actor.rig.set_process(false)
	actor.camera.current = false
	var hud := actor.get_node_or_null("SwimmingHUD")
	if hud != null:
		hud.hide()
		hud.set_process(false)
	actor.simulation_stepped.connect(on_actor_step.bind(actor))
	actor.actions.started.connect(func(_id):
		if measured:
			actions_started += 1
			frame_actions += 1)
	actor.reactions.recovered.connect(func():
		if measured: recovery_count += 1)
	actor.name = "BenchmarkCharacter%s" % index
	return actor

func next_case() -> void:
	changing = true
	measured = false
	actors.clear()
	intent.clear()
	next_actions.clear()
	alternation.clear()
	if is_instance_valid(world): world.free()
	current_case += 1
	if current_case >= cases.size():
		finish()
		return
	var entry := cases[current_case]
	world = Node3D.new()
	add_child(world)
	services = get_node("/root/GameSession").configure_world(world)
	var slope: bool = entry.scenario == "slope"
	var floor := Shapes.solid(world,Vector3(80,0.5,100),Vector3(0,-0.25,0),Color("48535a"))
	if slope: floor.rotation.x = deg_to_rad(30)
	var spawn_start := Time.get_ticks_usec()
	for index in int(entry.characters):
		var x: float = (index%5-2)*3.5
		var z: float = (floor(index/5.0)-1)*4.0
		var y: float = -z*tan(deg_to_rad(30))+0.05 if slope else 0.05
		var actor := spawn(Vector3(x,y,z),index)
		actors.append(actor)
		var requested := Intent.new()
		intent.append(requested)
		actor.submit_intent(requested)
		next_actions.append(index*0.025)
		alternation.append(index%2)
	entry.spawn_ms = (Time.get_ticks_usec()-spawn_start)/1000.0
	camera.current = true
	camera.position = Vector3(16,24,28)
	camera.look_at(Vector3(0,2,0))
	for tick in 12: await get_tree().physics_frame
	if entry.scenario == "crouch":
		for actor in actors: actor.posture.toggle()
	frames.clear()
	physics_cpu.clear()
	render_cpu.clear()
	physics_frame = -1
	physics_count = 0
	physics_total_us = 0
	actions_started = 0
	recovery_count = 0
	slow_frames.clear()
	omitted_slow_frames = 0
	frame_pose_us = 0
	frame_physics_ticks = 0
	frame_actions = 0
	started_us = Time.get_ticks_usec()
	previous_frame_us = started_us
	changing = false
	label.text = "Animation benchmark • %s • %s characters" % [entry.scenario,entry.characters]

func _physics_process(_delta: float) -> void:
	if changing: return
	var age := (Time.get_ticks_usec()-started_us)/1000000.0
	var scenario: String = cases[current_case].scenario
	for index in actors.size():
		var actor := actors[index]
		if scenario in ["slope","crouch"]:
			var direction := Vector3.FORWARD if int(age/1.5)%2 == 0 else Vector3.BACK
			intent[index].movement = direction
			intent[index].sprint = scenario == "slope" and index%2 == 1
		elif scenario == "combat" and age >= next_actions[index] and actor.actions.is_available():
			actor.stamina = actor.resources.definition.stamina_max
			actor.mana = actor.resources.definition.mana_max
			actor.actions.request("light" if alternation[index]%2 == 0 else "cast")
			alternation[index] += 1
			next_actions[index] = age+0.1
		elif scenario == "recovery" and age >= next_actions[index] and not actor.reactions.active:
			actor.reactions.begin(false,false)
			next_actions[index] = age+0.5

func on_actor_step(_delta: float, actor: CharacterBody3D) -> void:
	if not measured or changing: return
	var frame := Engine.get_physics_frames()
	if frame != physics_frame:
		physics_frame = frame
		physics_count = 0
		physics_total_us = 0
	physics_total_us += actor.pose_driver.sample_microseconds
	frame_pose_us += actor.pose_driver.sample_microseconds
	physics_count += 1
	if physics_count == actors.size():
		physics_cpu.append(physics_total_us/1000.0)
		frame_physics_ticks += 1

func _process(_delta: float) -> void:
	if changing: return
	var now := Time.get_ticks_usec()
	var elapsed := (now-started_us)/1000000.0
	if not measured and elapsed >= warmup_seconds:
		measured = true
		start_memory = rss()
		previous_frame_us = now
	elif measured:
		var interval := (now-previous_frame_us)/1000.0
		frames.append(interval)
		var render_us := 0
		for actor in actors:
			if not actor.model.is_processing(): continue
			var duration: Variant = actor.pose_driver.get("render_microseconds")
			if duration != null: render_us += int(duration)
		render_cpu.append(render_us/1000.0)
		if trace_spikes and interval > 1000.0/30.0:
			if slow_frames.size() < 512:
				slow_frames.append({"elapsed_seconds":elapsed-warmup_seconds,"frame_ms":interval,"physics_ticks":frame_physics_ticks,"pose_cpu_ms":frame_pose_us/1000.0,"render_pose_ms":render_us/1000.0,"actions_started":frame_actions,"projectiles":services.transients.size()})
			else: omitted_slow_frames += 1
		frame_pose_us = 0
		frame_physics_ticks = 0
		frame_actions = 0
		previous_frame_us = now
	if elapsed >= warmup_seconds+measurement_seconds:
		var entry := cases[current_case].duplicate()
		entry.frame_ms = distribution(frames)
		entry.animation_physics_ms = distribution(physics_cpu)
		entry.animation_render_ms = distribution(render_cpu)
		entry.memory_start = start_memory
		entry.memory_end = rss()
		entry.actions_started = actions_started
		entry.recoveries_completed = recovery_count
		entry.measurement_seconds = maxf(0,elapsed-warmup_seconds)
		if trace_spikes:
			entry.slow_frames = slow_frames.duplicate()
			entry.omitted_slow_frames = omitted_slow_frames
		results.append(entry)
		print("ANIMATION BENCHMARK ",JSON.stringify(entry))
		changing = true
		next_case.call_deferred()

func distribution(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty(): return {"samples":0,"p50":0.0,"p95":0.0,"p99":0.0,"max":0.0,"mean":0.0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in ordered: total += value
	return {"samples":ordered.size(),"p50":ordered[int(ceil(0.50*ordered.size()))-1],"p95":ordered[int(ceil(0.95*ordered.size()))-1],"p99":ordered[int(ceil(0.99*ordered.size()))-1],"max":ordered[-1],"mean":total/ordered.size()}

func finish() -> void:
	var report := {
		"configuration":{"resolution":[1280,720],"physics_hz":Engine.physics_ticks_per_second,"render_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"rendering_method":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"display_server":DisplayServer.get_name(),"debug_build":OS.is_debug_build(),"godot_version":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"warmup_seconds":warmup_seconds,"measurement_seconds":measurement_seconds,"headless_smoke_only":DisplayServer.get_name()=="headless"},
		"startup_to_ready_ms":startup_ms,"spawn":spawn_stats,"results":results,"trace_spikes":trace_spikes,
		"notes":["Whole-frame values are uncapped wall-clock frame intervals; run an exported release on the real GPU without concurrent tests.","Physics animation CPU is summed once per character physics completion; render CPU is summed once per displayed frame.","Scenarios include production motor/action/IK/equipment costs, shadows and spell effects; individual player camera and HUD processing is disabled.","RSS is sampled at each measurement boundary; peak RSS is process-wide Linux VmHWM.","startup_to_ready_ms includes the ordinary game bootstrap before the opt-in benchmark scene; spawn values use already loaded resources.","Optional slow-frame traces record intervals above 33.33 ms with intervening physics ticks, pose CPU and action starts. These correlations are not an attribution of GPU or whole-game CPU cost; each case retains at most 512 records."]}
	var directory := ProjectSettings.globalize_path(output.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(output,FileAccess.WRITE) if error == OK else null
	if file == null:
		push_error("Could not write animation benchmark report: "+output)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("ANIMATION BENCHMARK COMPLETE: ",ProjectSettings.globalize_path(output))
	get_tree().quit()
