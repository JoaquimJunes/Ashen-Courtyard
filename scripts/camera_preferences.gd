class_name CameraPreferences
extends RefCounted

const PATH := "user://camera_settings.cfg"
const DEFAULTS := {"side": 1.0, "fov": 65.0, "distance": 3.8, "offset": 0.7,
 "height": 1.65, "sensitivity": 1.0, "smoothing": 0.12, "invert_y": false}
const LIMITS := {"fov": Vector2(50,95), "distance": Vector2(2.0,6.0),
 "offset": Vector2(0,1.2), "height": Vector2(1.2,2.2),
 "sensitivity": Vector2(0.25,2.5), "smoothing": Vector2(0,0.35)}
static var values: Dictionary = DEFAULTS.duplicate()
static var loaded := false

static func set_value(key: String, value: Variant) -> void:
 if not DEFAULTS.has(key): return
 if key == "invert_y": values[key] = bool(value)
 elif value is float or value is int:
  if not is_finite(float(value)): return
  if key == "side": values[key] = -1.0 if float(value) < 0 else 1.0
  else: values[key] = clampf(float(value), LIMITS[key].x, LIMITS[key].y)

static func load_settings(path: String = PATH) -> void:
 values = DEFAULTS.duplicate()
 var config := ConfigFile.new()
 if config.load(path) == OK:
  for key in DEFAULTS: set_value(key, config.get_value("camera",key,DEFAULTS[key]))
 loaded = true

static func save_settings(path: String = PATH) -> Error:
 var config := ConfigFile.new()
 for key in values: config.set_value("camera",key,values[key])
 return config.save(path)

static func reset() -> void:
 values = DEFAULTS.duplicate()
