extends CanvasLayer
## Only the 3D image is pixelated. HUD and menus render above this layer.
func _ready() -> void:
 preload("res://features/ui/display_options.gd").load_preferences()
 layer = 0
 process_mode = Node.PROCESS_MODE_ALWAYS
 RenderingServer.global_shader_parameter_set("psx_enabled",PSXStyle.enabled)
 var rect := ColorRect.new()
 rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
 var mat := ShaderMaterial.new()
 mat.shader = preload("res://shaders/psx_screen.gdshader")
 rect.material = mat
 add_child(rect)

func _unhandled_input(event: InputEvent) -> void:
 if event.is_action_pressed("retro"):
  PSXStyle.enabled = not PSXStyle.enabled
  RenderingServer.global_shader_parameter_set("psx_enabled",PSXStyle.enabled)
  get_viewport().set_input_as_handled()
