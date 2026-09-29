extends "res://features/ui/settings_page.gd"
const VIEW_STATE_PATH := "user://controls_menu.cfg"
var widgets: Dictionary = {}
var action_rows: Dictionary = {}
var draft: Dictionary = {}
var waiting := ""
var save_path := GameInput.PATH
var categories: OptionButton
var empty: Label

func _ready() -> void:
 build("Controls")
 categories = OptionButton.new()
 for name in GameInput.CATEGORIES: categories.add_item(name)
 restore_category()
 categories.item_selected.connect(select_category)
 column.add_child(categories)
 column.move_child(categories,1)
 var rows := VBoxContainer.new()
 fields.add_child(rows)
 for action in GameInput.DEFAULTS:
  var row := HBoxContainer.new()
  rows.add_child(row)
  action_rows[action] = row
  var title := Label.new()
  title.text = GameInput.LABELS[action]
  title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  row.add_child(title)
  var binding := Button.new()
  binding.custom_minimum_size = Vector2(240,36)
  binding.pressed.connect(start_capture.bind(action))
  row.add_child(binding)
  widgets[action] = binding
 empty = Style.paragraph(fields,"Interaction bindings will appear when those mechanics are implemented.")

func restore_category() -> void:
 var config := ConfigFile.new()
 if config.load(VIEW_STATE_PATH) != OK: return
 var category: Variant = config.get_value("controls","category","Movement")
 if category is String and GameInput.CATEGORIES.has(category):
  categories.select(GameInput.CATEGORIES.keys().find(category))

func select_category(_index: int) -> void:
 waiting = ""
 refresh()
 show_category()
 # Navigation is remembered immediately, independently of unapplied bindings.
 var config := ConfigFile.new()
 config.load(VIEW_STATE_PATH)
 config.set_value("controls","category",categories.get_item_text(categories.selected))
 if config.save(VIEW_STATE_PATH) != OK:
  message.text = "Category selected, but this menu preference could not be saved."

func show_category() -> void:
 var actions: Array = GameInput.CATEGORIES[categories.get_item_text(categories.selected)]
 for action in action_rows: action_rows[action].visible = action in actions
 empty.visible = actions.is_empty()
 categories.grab_focus()

func dirty() -> bool: return draft != GameInput.bindings

func discard() -> void:
 waiting = ""
 draft = GameInput.bindings.duplicate()
 refresh()

func restore_defaults() -> void:
 waiting = ""
 draft = GameInput.DEFAULTS.duplicate()
 refresh()
 message.text = "All binding categories restored. Choose Apply to confirm." if dirty() else "Already using defaults."

func open() -> void:
 draft = GameInput.bindings.duplicate()
 waiting = ""
 message.text = "Click a binding, then press a key or mouse button.\nEscape cancels; it always remains available for menus."
 refresh()
 show()
 show_category()

func refresh() -> void:
 refresh_apply()
 for action in widgets: widgets[action].text = GameInput.binding_name(draft[action])

func start_capture(action: String) -> void:
 waiting = action
 widgets[action].text = "Press an input…"
 message.text = "Binding: %s. Escape cancels. Mouse wheel and key combinations are not supported." % GameInput.LABELS[action]

func capture_input(event: InputEvent) -> bool:
 # The shared menu routes capture before shortcuts, GUI navigation or gameplay.
 if not is_visible_in_tree() or waiting.is_empty(): return false
 if event is InputEventKey and event.pressed and not event.echo:
  var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
  if code == KEY_ESCAPE:
   waiting = ""
   refresh()
   message.text = "Binding unchanged."
  elif (event.ctrl_pressed and code != KEY_CTRL) or (event.alt_pressed and code != KEY_ALT) or (event.meta_pressed and code != KEY_META) or (event.shift_pressed and code != KEY_SHIFT):
   message.text = "Press one key at a time; key combinations are not supported."
  else: assign(code)
 elif event is InputEventMouseButton and event.pressed:
  assign(-event.button_index)
 return true

func assign(code: int) -> void:
 if not GameInput.valid_binding(code):
  message.text = "Choose a supported keyboard key or mouse button (not the wheel)."
  return
 for action in draft:
  if action != waiting and draft[action] == code:
   message.text = "%s is already used by %s. Choose another input or press Escape." % [GameInput.binding_name(code),GameInput.LABELS[action]]
   return
 draft[waiting] = code
 waiting = ""
 refresh()
 message.text = "Binding updated. Choose Apply to confirm." if dirty() else "Binding unchanged."

func save() -> void:
 if GameInput.save_settings(draft,save_path) != OK:
  message.text = "Could not save bindings. Your previous controls remain active."
  return
 refresh_apply()
 message.text = "Controls applied."
 applied.emit()

func cancel() -> void:
 close()
