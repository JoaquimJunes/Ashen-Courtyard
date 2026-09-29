extends "res://features/ui/settings_page.gd"
const PATH := "user://display_settings.cfg"
static var loaded := false
var draft := true
var toggle: CheckButton
var save_path := PATH

static func load_preferences() -> void:
	if loaded: return
	loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		var value: Variant = config.get_value("display","retro",true)
		if value is bool: PSXStyle.enabled = value
	RenderingServer.global_shader_parameter_set("psx_enabled",PSXStyle.enabled)

func _ready() -> void:
	build("Display")
	toggle = CheckButton.new()
	toggle.text = "PS1 effects"
	toggle.toggled.connect(func(value):
		draft = value
		refresh_apply()
		message.text = "Unapplied changes." if dirty() else "No unapplied changes.")
	fields.add_child(toggle)
	Style.paragraph(fields,"Interface text stays crisp independently of the 3D effects.")
	PSXStyle.changes.enabled_changed.connect(on_effects_changed)

func on_effects_changed(previous: bool, current: bool) -> void:
	# Follow external shortcuts when this editor had no pending edit. Otherwise
	# retain the draft, then compare it against the new active value.
	if draft == previous: draft = current
	toggle.set_pressed_no_signal(draft)
	refresh_apply()
	message.text = "Unapplied changes." if dirty() else "PS1 effects updated."

func open() -> void:
	discard()
	show()
	toggle.grab_focus()

func discard() -> void:
	draft = PSXStyle.enabled
	toggle.set_pressed_no_signal(draft)
	refresh_apply()
	message.text = "Changes take effect when you choose Apply."

func dirty() -> bool: return draft != PSXStyle.enabled

func restore_defaults() -> void:
	draft = true
	toggle.set_pressed_no_signal(draft)
	refresh_apply()
	message.text = "Display defaults restored. Choose Apply to confirm." if dirty() else "Already using defaults."

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("display","retro",draft)
	if config.save(save_path) != OK:
		message.text = "Could not save. Previous display settings remain active."
		return
	PSXStyle.enabled = draft
	RenderingServer.global_shader_parameter_set("psx_enabled",draft)
	refresh_apply()
	message.text = "Display settings applied."
	applied.emit()
