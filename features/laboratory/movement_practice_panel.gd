extends PanelContainer
signal closed
var lab: Node3D
var hud: CanvasLayer
var mode_selector: OptionButton
var instructions: Label

func _ready() -> void:
	theme = preload("res://features/ui/ui_style.gd").make_theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	column.add_child(hud.label("RUNNING & DODGE REVIEW",25))
	instructions = hud.label("",16)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(instructions)
	hud.button(column,"Running course — turns, ramps and steps",func(): start_station(1))
	hud.button(column,"Dodge gaps — low obstacles and raised landings",func(): start_station(2))
	column.add_child(hud.label("Optional hub combat practice",19))
	mode_selector = OptionButton.new()
	mode_selector.add_item("Free movement / combat off",0)
	mode_selector.add_item("Stationary target / combat enabled",1)
	mode_selector.add_item("Timed overhead attacks / 10 damage",2)
	column.add_child(mode_selector)
	hud.button(column,"Start hub practice",start_hub)
	preload("res://features/ui/ui_style.gd").paragraph(column,"The target stays in the hub. Leaving it turns combat off.\nReset station restores both characters; death restarts the attempt.\nMovement is shared with the courtyard: forward dive and grounded side/back rolls.")
	hud.button(column,"Back to directory",close)
	hide()

func open() -> void:
	mode_selector.select(lab.practice.mode)
	instructions.text = "%s/%s/%s/%s Move  ·  %s Sprint  ·  %s Dodge\n%s Lock on in practice  ·  %s Diagnostics  ·  %s PS1 effects\nForward dive + grounded side/back rolls (0.70 s)" % [GameInput.key("forward"),GameInput.key("left"),GameInput.key("back"),GameInput.key("right"),GameInput.key("sprint"),GameInput.key("dodge"),GameInput.key("lock"),GameInput.key("diagnostics"),GameInput.key("retro")]
	show()
	mode_selector.grab_focus()

func close() -> void:
	hide()
	closed.emit()

func start_station(id: int) -> void:
	lab.go_to_station(id)
	hide()
	hud.toggle_pause()

func start_hub() -> void:
	lab.set_practice_mode(mode_selector.get_selected_id())
	hide()
	hud.toggle_pause()
