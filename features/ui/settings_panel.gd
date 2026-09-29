extends VBoxContainer
signal applied
const VIEW_STATE_PATH := "user://settings_menu.cfg"
const Style = preload("res://features/ui/ui_style.gd")
var editors: Dictionary = {}
var tabs: Dictionary = {}
var selected := "Camera"

func _ready() -> void:
	var row := HBoxContainer.new()
	add_child(row)
	for name in ["Camera","Controls","Display"]:
		tabs[name] = Style.button(row,name,select.bind(name))
		tabs[name].toggle_mode = true
	var paths := {"Camera":"res://scripts/camera_options.gd","Controls":"res://scripts/keybinding_options.gd","Display":"res://features/ui/display_options.gd"}
	for name in paths:
		var editor: PanelContainer = load(paths[name]).new()
		add_child(editor)
		editors[name] = editor
		editor.applied.connect(func(): applied.emit())
	var config := ConfigFile.new()
	if config.load(VIEW_STATE_PATH) == OK:
		var tab: Variant = config.get_value("settings","tab","Camera")
		if tab is String and editors.has(tab): selected = tab

func open() -> void:
	for editor in editors.values(): editor.open()
	select(selected,false)

func select(name: String, remember: bool = true) -> void:
	if not editors.has(name): return
	var changed := selected != name
	selected = name
	for key in editors:
		editors[key].visible = key == name
		tabs[key].set_pressed_no_signal(key == name)
	tabs[name].grab_focus()
	if remember and changed:
		var config := ConfigFile.new()
		config.set_value("settings","tab",name)
		if config.save(VIEW_STATE_PATH) != OK:
			editors[name].message.text = "Tab selected, but this menu preference could not be saved."

func dirty() -> bool:
	for editor in editors.values():
		if editor.dirty(): return true
	return false

func discard() -> void:
	for editor in editors.values(): editor.discard()

func apply_changes() -> String:
	# Apply every changed tab; a failed save leaves the remaining draft intact.
	for name in editors:
		var editor: PanelContainer = editors[name]
		if not editor.dirty(): continue
		editor.save()
		if editor.dirty(): return name
	return ""
