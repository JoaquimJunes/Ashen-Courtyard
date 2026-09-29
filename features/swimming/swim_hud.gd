extends CanvasLayer
## Camera immersion is independent of the character's breathing sample.
const Water = preload("res://features/swimming/water_volume.gd")
var actor: CharacterBody3D
var tint: ColorRect
var panel: VBoxContainer
var breath: ProgressBar
var warning: Label
var controls: Label
var camera_submerged := false

func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	tint = ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.03,0.25,0.30,0.20)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tint)
	panel = VBoxContainer.new()
	panel.position = Vector2(32,190)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	warning = Label.new()
	warning.add_theme_font_size_override("font_size",15)
	panel.add_child(warning)
	breath = ProgressBar.new()
	breath.custom_minimum_size = Vector2(230,12)
	breath.show_percentage = false
	breath.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(breath)
	controls = Label.new()
	controls.add_theme_font_size_override("font_size",13)
	panel.add_child(controls)
	actor.resources.breath_changed.connect(update_breath)
	update_breath(actor.resources.breath,actor.resources.maximum_breath)
	_process(0)

func update_breath(value: float, maximum: float) -> void:
	breath.max_value = maximum
	breath.value = value
	warning.text = "OUT OF BREATH — SURFACE!" if value <= 0 else ("LOW BREATH — SURFACE" if value <= maximum*0.25 else "BREATH")
	warning.modulate = Color("efb775") if value <= maximum*0.25 else Color("dfefea")

func _process(_delta: float) -> void:
	if not is_instance_valid(actor) or actor.camera == null: return
	camera_submerged = Water.at(actor,actor.camera.global_position) != null
	tint.visible = camera_submerged
	panel.visible = not actor.dead and (actor.swimming.active or actor.swimming.head_detector.head_submerged or actor.resources.breath < actor.resources.maximum_breath)
	controls.text = "%s Ascend · %s Dive · %s Swim faster\nSwim toward a low ledge to climb out" % [GameInput.key("jump"),GameInput.key("crouch"),GameInput.key("sprint")] if actor.swimming.active else "Raise your head above water to breathe"
