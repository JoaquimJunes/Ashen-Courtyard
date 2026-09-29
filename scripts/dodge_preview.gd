extends Node3D
## Review controls around the same character scene used by both playable worlds.
## No second collision integrator, pose driver, or action timeline.
enum Phase { PUSH_OFF, DIVE, ROLL, FINISHED }
const DEFAULT_TUNING = preload("res://data/combat.tres")
@export var raised_gap_review := false
var start_transform := Transform3D.IDENTITY
var push_duration: float = DEFAULT_TUNING.dodge_forward.preparation
var travel_distance: float = DEFAULT_TUNING.dodge_forward.distance
var phase := Phase.PUSH_OFF
var phase_time := 0.0
var elapsed := 0.0
var remaining := 0.0
var landing_time := -1.0
var playing := true:
	set(value):
		playing = value
		if is_instance_valid(body):
			body.set_physics_process(value or stepping)
			if not body.forward_dive.active: knight.set_process(value)
var playback_speed := 1.0:
	set(value):
		playback_speed = value
		Engine.time_scale = value
var body: CharacterBody3D
var knight: Node3D
var pose: RefCounted:
	get: return body.forward_dive.pose
var heading: Label
var diagnostics: Label
var pause_button: Button
var old_psx: bool
var old_time_scale := 1.0
var ready_to_simulate := false
var grounded := false
var waiting_for_floor := true
var stepping := false
var start_requested := false

func _ready() -> void:
	GameInput.configure()
	old_time_scale = Engine.time_scale
	old_psx = PSXStyle.enabled
	RenderingServer.global_shader_parameter_set("psx_enabled",false)
	build_stage()
	build_ui()
	restart()
	ready_to_simulate = true

func _exit_tree() -> void:
	Engine.time_scale = old_time_scale
	RenderingServer.global_shader_parameter_set("psx_enabled",old_psx)

func build_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("161e2b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d5e3f5")
	world.environment.ambient_light_energy = 0.7
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	light.light_energy = 1.6
	light.shadow_enabled = true
	add_child(light)
	if raised_gap_review:
		var rig := preload("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
		rig.show_labels = false
		add_child(rig)
		start_transform = rig.get_node("DiveStart").global_transform
		light.light_energy = 0.9
		world.environment.ambient_light_energy = 0.45
		for values: Array in [["0.60 m",Vector3(1.55,0.3,1.5)],
			["1.00 m",Vector3(1.55,0.45,-4.0)],["0.60 m gap",Vector3(1.55,-0.1,-0.3)]]:
			var label := Label3D.new()
			label.text = values[0]
			label.position = values[1]
			label.font_size = 40
			label.pixel_size = 0.005
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			add_child(label)
	else:
		Shapes.solid(self, Vector3(9,0.2,12), Vector3(0,-0.1,-2), Color("586574"))
	for meter in range(-1,7) if not raised_gap_review else []:
		Shapes.box(self, Vector3(2.4,0.006,0.025), Vector3(0,0.006,-meter), Color("9aaabc"))
		var label := Label3D.new()
		label.text = "%d m" % meter
		label.font_size = 48
		label.pixel_size = 0.004
		label.position = Vector3(0,0.012,-meter)
		label.position.x = 1.55
		label.rotation_degrees.x = -90
		add_child(label)
	if not raised_gap_review:
		Shapes.box(self,Vector3(0.025,0.008,8),Vector3(0,0.006,-2.5),Color("cbb57d"))
	body = preload("res://scenes/player.tscn").instantiate()
	body.combat_enabled = false
	body.controller.manual = true
	add_child(body)
	body.set_process_unhandled_input(false)
	body.simulation_stepped.connect(after_character_step)
	body.actions.started.connect(func(_id: StringName): waiting_for_floor = false)
	knight = body.model
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.8
	camera.position = Vector3(9,3.3,-2.05)
	add_child(camera)
	camera.look_at(Vector3(0,0.75,-2.05))
	camera.current = true
	if raised_gap_review:
		camera.position = Vector3(9,3.2,-2.05)
		camera.look_at(Vector3(0,1.15,-2.05))

func build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := VBoxContainer.new()
	panel.position = Vector2(28,20)
	canvas.add_child(panel)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size",27)
	panel.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "FORWARD DODGE / motion study 03    •    Lean → dive → shoulder → roll → feet"
	panel.add_child(subtitle)
	diagnostics = Label.new()
	diagnostics.add_theme_font_size_override("font_size",17)
	panel.add_child(diagnostics)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",12)
	panel.add_child(controls)
	var replay := Button.new()
	replay.text = "Replay [R]"
	replay.pressed.connect(restart)
	controls.add_child(replay)
	pause_button = Button.new()
	pause_button.pressed.connect(toggle_pause)
	controls.add_child(pause_button)
	var step := Button.new()
	step.text = "Frame step [→]"
	step.pressed.connect(step_frame)
	controls.add_child(step)
	var speed := OptionButton.new()
	for label in ["1× normal", "0.25× slow"]: speed.add_item(label)
	speed.item_selected.connect(func(index: int): playback_speed = 1.0 if index == 0 else 0.25)
	controls.add_child(speed)
	var note := Label.new()
	note.text = "Shared playable character • 0.25 m dive / 0.55 s finish • R replay / Space pause / → step"
	if raised_gap_review:
		note.text = "Start 0.60 m → land 1.00 m • Gap 0.60 m • Adaptive clearance • R replay / Space pause / → step"
	note.position = Vector2(28,675)
	canvas.add_child(note)

func restart() -> void:
	body.reset_for_lab(start_transform)
	phase = Phase.PUSH_OFF
	phase_time = 0
	elapsed = 0
	remaining = travel_distance
	landing_time = -1
	grounded = false
	waiting_for_floor = true
	start_requested = false
	stepping = false
	playing = true
	refresh_ui()

func toggle_pause() -> void:
	playing = not playing
	refresh_ui()

func step_frame() -> void:
	if not ready_to_simulate: return
	stepping = true
	playing = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_R: restart()
		KEY_SPACE: toggle_pause()
		KEY_RIGHT: step_frame()

func after_character_step(delta: float) -> void:
	if waiting_for_floor:
		if body.is_on_floor() and not start_requested:
			start_requested = body.begin("dodge")
	elif phase != Phase.FINISHED:
		elapsed += delta
		var next: int = body.forward_dive.phase if body.forward_dive.active else Phase.FINISHED
		if next == Phase.ROLL and phase == Phase.DIVE: landing_time = elapsed
		phase = next
		phase_time = body.forward_dive.roll_time if phase == Phase.ROLL else body.forward_dive.time
		remaining = body.dodge_distance_left
		if phase == Phase.FINISHED:
			body.motor.stop()
			# The character already published this tick's completed exit pose.
			playing = false
	grounded = body.is_on_floor()
	if stepping:
		stepping = false
		playing = false
	refresh_ui()

func refresh_ui() -> void:
	heading.text = ["01  PUSH OFF", "02  LOW DIVE", "03  SHOULDER ROLL / RECOVERY", "04  FEET PLANTED"][phase]
	if raised_gap_review and phase == Phase.DIVE: heading.text = "02  ADAPTIVE DIVE / RAISED GAP"
	diagnostics.text = "Time %.2f s    |    Travel %.2f m    |    Height %.2f m    |    %s" % [elapsed,start_transform.origin.z-body.position.z,body.position.y,"GROUND" if grounded else "AIR"]
	pause_button.text = "Pause [Space]" if playing else "Play [Space]"
