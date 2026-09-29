extends "res://features/ui/settings_page.gd"
var widgets: Dictionary = {}
var readouts: Dictionary = {}
var draft: Dictionary = {}
var save_path := CameraPreferences.PATH

func _ready() -> void:
 build("Camera")
 draft = CameraPreferences.values.duplicate()
 var side_row := row(fields,"Shoulder side")
 var side := OptionButton.new()
 side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 side.add_item("Right shoulder")
 side.add_item("Left shoulder")
 side.item_selected.connect(func(index): edit("side",1.0 if index == 0 else -1.0))
 side_row.add_child(side)
 widgets.side = side
 slider(fields,"fov","Field of view",1.0,"°")
 slider(fields,"distance","Camera distance",0.1," m")
 slider(fields,"offset","Shoulder offset",0.05," m")
 slider(fields,"height","Camera height",0.05," m")
 slider(fields,"sensitivity","Mouse sensitivity",0.05,"×")
 slider(fields,"smoothing","Follow smoothing",0.01," s")
 var invert := CheckButton.new()
 invert.text = "Invert vertical mouse look"
 invert.toggled.connect(func(value): edit("invert_y",value))
 fields.add_child(invert)
 widgets.invert_y = invert
 refresh()

func row(column: Control, title: String) -> HBoxContainer:
 var line := HBoxContainer.new()
 line.custom_minimum_size.y = 30
 line.add_theme_constant_override("separation",14)
 column.add_child(line)
 var label := Label.new()
 label.text = title
 label.custom_minimum_size.x = 150
 line.add_child(label)
 return line

func slider(column: Control, key: String, title: String, step: float, suffix: String) -> void:
 var line := row(column,title)
 var control := HSlider.new()
 control.min_value = CameraPreferences.LIMITS[key].x
 control.max_value = CameraPreferences.LIMITS[key].y
 control.step = step
 control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 control.custom_minimum_size.x = 150
 line.add_child(control)
 var value := Label.new()
 value.custom_minimum_size.x = 70
 value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 line.add_child(value)
 control.value_changed.connect(func(number):
  edit(key,number)
  value.text = ("%.0f" % number if step >= 1 else "%.2f" % number) + suffix
 )
 widgets[key] = control
 readouts[key] = {"label":value,"step":step,"suffix":suffix}

func refresh() -> void:
 refresh_apply()
 for key in widgets:
  var value: Variant = draft[key]
  if key == "side": widgets[key].select(0 if float(value) > 0 else 1)
  elif key == "invert_y": widgets[key].set_pressed_no_signal(bool(value))
  else:
   widgets[key].set_value_no_signal(value)
   var info: Dictionary = readouts[key]
   info.label.text = ("%.0f" % value if info.step >= 1 else "%.2f" % value) + info.suffix

func edit(key: String, value: Variant) -> void:
 draft[key] = value
 refresh_apply()
 message.text = "Unapplied changes." if dirty() else "No unapplied changes."

func open() -> void:
 discard()
 show()
 widgets.side.grab_focus()

func discard() -> void:
 draft = CameraPreferences.values.duplicate()
 refresh()
 message.text = "Changes take effect when you choose Apply."

func dirty() -> bool: return draft != CameraPreferences.values

func restore_defaults() -> void:
 draft = CameraPreferences.DEFAULTS.duplicate()
 refresh()
 message.text = "Camera defaults restored. Choose Apply to confirm." if dirty() else "Already using defaults."

func save() -> void:
 var previous := CameraPreferences.values.duplicate()
 for key in draft: CameraPreferences.set_value(key,draft[key])
 if CameraPreferences.save_settings(save_path) != OK:
  CameraPreferences.values = previous
  message.text = "Could not save. Previous camera settings remain active."
  return
 draft = CameraPreferences.values.duplicate()
 refresh_apply()
 message.text = "Camera settings applied."
 applied.emit()
