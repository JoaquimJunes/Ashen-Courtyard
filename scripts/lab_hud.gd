extends CanvasLayer
## Lab UI host: compose the shared menu and optional diagnostics without legacy overlays.
var lab: Node3D
var panel: PanelContainer
var options: PanelContainer
var keybindings: PanelContainer
var practice_options: PanelContainer
var diagnostic_button: CheckButton
var selector: OptionButton
var resume: Button
var menu: CanvasLayer
var diagnostics_enabled: bool:
 get: return menu.live_enabled
 set(value): menu.set_debug(value)

func label(words: String, size: int = 18) -> Label:
 var node := Label.new()
 node.text = words
 node.add_theme_font_size_override("font_size",size)
 node.add_theme_color_override("font_color",Color("edf0e6"))
 node.add_theme_color_override("font_outline_color",Color("15232c"))
 node.add_theme_constant_override("outline_size",5)
 return node

func button(parent: Node, words: String, action: Callable) -> Button:
 var node := Button.new()
 node.text = words
 node.custom_minimum_size.y = 34
 node.pressed.connect(action)
 parent.add_child(node)
 return node

func _ready() -> void:
 layer = 2
 process_mode = Node.PROCESS_MODE_ALWAYS
 menu = preload("res://features/ui/pause_menu.tscn").instantiate()
 add_child(menu)
 menu.configure(lab.player,lab)
 panel = menu.panel
 options = menu.settings.editors.Camera
 keybindings = menu.settings.editors.Controls
 practice_options = menu.practice
 diagnostic_button = menu.live_toggle
 selector = menu.tools.station
 resume = menu.resume

func toggle_pause() -> void:
 menu.toggle_pause()
