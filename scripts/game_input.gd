class_name GameInput
extends RefCounted

const PATH := "user://keybindings.cfg"
const CATEGORIES := {"Movement":["forward","back","left","right","sprint","jump","dodge","crouch"],"Combat":["light","heavy","lock","spell_one","spell_two","cast","heal"],"Interaction":[],"Interface & Debugging":["pause","diagnostics","retro"]}
const DEFAULTS := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,"dodge":KEY_ALT,"jump":KEY_SPACE,"crouch":KEY_C,"light":-MOUSE_BUTTON_LEFT,"heavy":-MOUSE_BUTTON_RIGHT,"lock":KEY_Q,"spell_one":KEY_1,"spell_two":KEY_2,"cast":KEY_E,"heal":KEY_R,"pause":KEY_ESCAPE,"diagnostics":KEY_F3,"retro":KEY_F4}
const LABELS := {"forward":"Move forward","back":"Move backward","left":"Move left","right":"Move right","sprint":"Sprint","dodge":"Dodge","jump":"Jump","crouch":"Crouch / stand / hold to crawl","light":"Attack (tap / hold)","heavy":"Heavy attack","lock":"Lock on","spell_one":"Select spell 1","spell_two":"Select spell 2","cast":"Cast spell","heal":"Heal","pause":"Pause menu","diagnostics":"Diagnostics","retro":"PS1 effects"}
static var bindings: Dictionary = DEFAULTS.duplicate()
static var loaded := false

static func configure() -> void:
 if not loaded: load_settings()
 apply()

static func apply() -> void:
 for action in DEFAULTS:
  if not InputMap.has_action(action): InputMap.add_action(action)
  Input.action_release(action)
  InputMap.action_erase_events(action)
  var code: int = bindings[action]
  var event: InputEvent
  if code > 0:
   event = InputEventKey.new()
   event.physical_keycode = code
  else:
   event = InputEventMouseButton.new()
   event.button_index = -code
  InputMap.action_add_event(action,event)

static func valid_keycode(code: int) -> bool:
 # Physical bindings use Godot's named, unmodified Key values, not arbitrary
 # Unicode or a KeyModifierMask. Domains verified against Godot 4.6.2:
 # https://github.com/godotengine/godot/blob/4.6.2-stable/core/os/keyboard.h
 return ((code >= KEY_SPACE and code <= KEY_QUOTELEFT)
  or (code >= KEY_BRACELEFT and code <= KEY_ASCIITILDE)
  or code in [KEY_YEN,KEY_SECTION]
  or (code >= KEY_ESCAPE and code <= KEY_F35)
  or code in [KEY_MENU,KEY_HYPER,KEY_HELP]
  or (code >= KEY_BACK and code <= KEY_VOLUMEUP)
  or (code >= KEY_MEDIAPLAY and code <= KEY_JIS_KANA)
  or (code >= KEY_KP_MULTIPLY and code <= KEY_KP_9))

static func valid_binding(code: int) -> bool:
 return valid_keycode(code) if code > 0 else -code in [1,2,3,8,9]

static func valid(candidate: Dictionary) -> bool:
 if candidate.size() != DEFAULTS.size(): return false
 var used: Array = []
 for action in DEFAULTS:
  if not candidate.has(action) or not candidate[action] is int: return false
  var code: int = candidate[action]
  if not valid_binding(code): return false
  if code == KEY_ESCAPE and action != "pause": return false
  if code in used: return false
  used.append(code)
 return true

static func load_settings(path: String = PATH) -> void:
 bindings = DEFAULTS.duplicate()
 var config := ConfigFile.new()
 if config.load(path) == OK:
  var candidate: Dictionary = {}
  for action in DEFAULTS: candidate[action] = config.get_value("bindings",action,DEFAULTS[action])
  # Migrate newly introduced actions without replacing existing bindings.
  var occupied: Array = []
  for action in DEFAULTS:
   if config.has_section_key("bindings",action): occupied.append(candidate[action])
  for action in DEFAULTS:
   if config.has_section_key("bindings",action): continue
   var choices: Array = [DEFAULTS[action],KEY_SPACE,KEY_ALT,KEY_F,KEY_C,KEY_CTRL,KEY_V,KEY_J,KEY_K,KEY_L,KEY_U,KEY_I,KEY_O]
   choices.append_array(range(KEY_A,KEY_Z+1))
   choices.append_array(range(KEY_F1,KEY_F12+1))
   for key_code in choices:
    if key_code not in occupied:
     candidate[action] = key_code
     occupied.append(key_code)
     break
  # F8 is Godot's Stop shortcut. Upgrade the old default without taking a
  # key from another action or replacing any other saved controls.
  if config.get_value("format","version",0) == 0 and candidate.retro == KEY_F8:
   var choices: Array = [KEY_F4,KEY_P,KEY_O,KEY_I,KEY_U]
   choices.append_array(range(KEY_A,KEY_Z+1))
   for key_code in choices:
    if key_code not in candidate.values():
     candidate.retro = key_code
     break
  if valid(candidate): bindings = candidate
 loaded = true

static func save_settings(candidate: Dictionary, path: String = PATH) -> Error:
 if not valid(candidate): return ERR_INVALID_DATA
 var config := ConfigFile.new()
 config.set_value("format","version",1)
 for action in DEFAULTS: config.set_value("bindings",action,candidate[action])
 var result := config.save(path)
 if result == OK:
  bindings = candidate.duplicate()
  loaded = true
  apply()
 return result

static func binding_name(code: int) -> String:
 match code:
  -1: return "Left mouse"
  -2: return "Right mouse"
  -3: return "Middle mouse"
  -8: return "Mouse 4"
  -9: return "Mouse 5"
 return OS.get_keycode_string(code)

static func key(action: String) -> String:
 return binding_name(bindings[action])

static func pause_pressed(event: InputEvent) -> bool:
 # Escape always provides a way back, even after rebinding Pause.
 return event.is_action_pressed("pause") or escape_pressed(event)

static func escape_pressed(event: InputEvent) -> bool:
 return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
