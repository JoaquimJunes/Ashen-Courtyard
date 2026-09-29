extends PanelContainer
## Editors own drafts only. Apply publishes through the existing preference service.
signal closed
signal applied
const Style = preload("res://features/ui/ui_style.gd")
var message: Label
var column: VBoxContainer
var fields: VBoxContainer
var apply_button: Button
var reset_button: Button

func build(title: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = Style.make_theme()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column = VBoxContainer.new()
	add_child(column)
	column.add_child(Style.text(title,24))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	fields = VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	message = Style.paragraph(column,"Changes take effect when you choose Apply.")
	message.custom_minimum_size.y = 44
	var actions := HBoxContainer.new()
	column.add_child(actions)
	reset_button = Style.button(actions,"Reset to defaults",restore_defaults)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	apply_button = Style.button(actions,"Apply",save)
	apply_button.hide()
	apply_button.disabled = true
	hide()

func refresh_apply() -> void:
	var changed := dirty()
	if not changed and apply_button.has_focus(): reset_button.grab_focus()
	apply_button.visible = changed
	apply_button.disabled = not changed

func restore_defaults() -> void: pass
func save() -> void: pass
func dirty() -> bool: return false
func discard() -> void: pass

func close() -> void:
	discard()
	hide()
	closed.emit()
