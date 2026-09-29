extends SceneTree
const TEST_PATH := "/tmp/ashen-test-keybindings.cfg"
const Controls = preload("res://scripts/keybinding_options.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok: print("PASS: ",description)
 else:
  failures += 1
  push_error(description)
func key_event(code: int) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.pressed = true
 return event
func settle() -> void:
 for i in 4: await process_frame
func run() -> void:
 GameInput.bindings = GameInput.DEFAULTS.duplicate()
 GameInput.loaded = true
 GameInput.configure()
 var changed := GameInput.bindings.duplicate()
 changed.forward = KEY_UP
 changed.pause = KEY_P
 changed.light = -MOUSE_BUTTON_XBUTTON1
 check(GameInput.save_settings(changed,TEST_PATH) == OK,"Custom keyboard and mouse bindings save")
 GameInput.bindings = GameInput.DEFAULTS.duplicate()
 GameInput.load_settings(TEST_PATH)
 GameInput.configure()
 check(GameInput.bindings == changed,"Bindings survive loading from disk")
 check(key_event(KEY_UP).is_action_pressed("forward") and not key_event(KEY_W).is_action_pressed("forward"),"Remapping replaces the default movement key")
 check(GameInput.pause_pressed(key_event(KEY_ESCAPE)) and GameInput.pause_pressed(key_event(KEY_P)),"Escape remains available after remapping pause")
 var bad := changed.duplicate()
 bad.back = KEY_UP
 check(GameInput.save_settings(bad,TEST_PATH) == ERR_INVALID_DATA and GameInput.bindings == changed,"Conflicts are rejected without changing active bindings")
 check(GameInput.save_settings(GameInput.DEFAULTS,"/missing/keybindings.cfg") != OK and GameInput.bindings == changed,"Failed saves preserve active controls")
 var config := ConfigFile.new()
 check(GameInput.DEFAULTS.retro == KEY_F4,"PS1 default avoids Godot's F8 Stop shortcut")
 for action in GameInput.DEFAULTS: config.set_value("bindings",action,GameInput.DEFAULTS[action])
 config.set_value("bindings","retro",KEY_F8)
 config.set_value("bindings","forward",KEY_UP)
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.retro == KEY_F4 and GameInput.bindings.forward == KEY_UP,"Legacy F8 migrates without losing custom controls")
 config.set_value("bindings","diagnostics",KEY_F4)
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.diagnostics == KEY_F4 and GameInput.bindings.retro == KEY_P and GameInput.valid(GameInput.bindings),"Migration keeps occupied F4 and chooses a free PS1 key")
 check(GameInput.save_settings(GameInput.bindings,TEST_PATH) == OK,"Migrated bindings save")
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.retro == KEY_P and GameInput.bindings.forward == KEY_UP,"Migrated controls survive reload")
 config.set_value("bindings","retro",KEY_O)
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.retro == KEY_O,"Existing custom PS1 shortcut stays unchanged")
 config = ConfigFile.new()
 check(GameInput.DEFAULTS.jump == KEY_SPACE and GameInput.DEFAULTS.dodge == KEY_ALT,"Fresh defaults bind Space jump and Alt dodge")
 for action in GameInput.DEFAULTS:
  if action != "jump": config.set_value("bindings",action,KEY_SPACE if action == "dodge" else GameInput.DEFAULTS[action])
 config.set_value("bindings","forward",KEY_UP)
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.dodge == KEY_SPACE and GameInput.bindings.forward == KEY_UP and GameInput.bindings.jump == KEY_ALT,"Old saved Space dodge and custom movement survive Jump migration")
 config.set_value("bindings","sprint",KEY_ALT)
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 check(GameInput.bindings.sprint == KEY_ALT and GameInput.bindings.jump == KEY_F and GameInput.valid(GameInput.bindings),"Migration chooses an unused Jump key when Space and Alt are occupied")
 config = ConfigFile.new()
 config.set_value("bindings","forward","invalid")
 config.save(TEST_PATH)
 GameInput.load_settings(TEST_PATH)
 GameInput.configure()
 check(GameInput.bindings == GameInput.DEFAULTS,"Malformed saved data falls back to playable defaults")
 # Invalid saved UI state must not prevent the Controls panel from opening.
 var view_state := ConfigFile.new()
 view_state.set_value("controls","category","Removed category")
 view_state.save(Controls.VIEW_STATE_PATH)
 for scene in ["arena","movement_lab"]:
  change_scene_to_file("res://scenes/%s.tscn" % scene)
  await settle()
  var hud = current_scene.hud
  if scene == "arena": current_scene.boss.frozen = true
  hud.toggle_pause()
  var parent_panel: PanelContainer = hud.overlay if scene == "arena" else hud.panel
  var entry: Button = hud.menu.navigation.Settings
  check(is_instance_valid(entry),scene+": settings entry exists")
  entry.pressed.emit()
  hud.menu.settings.select("Controls")
  var options = hud.keybindings
  options.save_path = TEST_PATH
  check(options.categories.get_item_text(options.categories.selected) == ("Movement" if scene == "arena" else "Combat"),scene+": category falls back safely or restores across levels")
  options.categories.select(1)
  options.categories.item_selected.emit(1)
  check(not options.dirty() and not options.apply_button.visible,scene+": category selection does not create unapplied bindings")
  view_state = ConfigFile.new()
  view_state.load(Controls.VIEW_STATE_PATH)
  check(view_state.get_value("controls","category") == "Combat",scene+": selected category is saved for future launches")
  hud.menu.back()
  entry.pressed.emit()
  hud.menu.settings.select("Controls")
  check(options.categories.get_item_text(options.categories.selected) == "Combat" and options.action_rows.light.visible and not options.action_rows.forward.visible,scene+": reopening restores the category and matching rows")
  check(paused and options.is_visible_in_tree() and parent_panel.visible,scene+": controls open while gameplay stays paused")
  options.start_capture("dodge")
  hud.menu.handle_input(key_event(KEY_W))
  check(options.waiting == "dodge" and options.draft.dodge == KEY_ALT,scene+": duplicate binding rejected")
  hud.menu.handle_input(key_event(KEY_ESCAPE))
  check(options.waiting == "" and options.visible,scene+": Escape cancels capture without closing menu")
  options.start_capture("dodge")
  var modified := key_event(KEY_Z)
  modified.ctrl_pressed = true
  hud.menu.handle_input(modified)
  check(options.waiting == "dodge",scene+": key combinations rejected")
  hud.menu.handle_input(key_event(KEY_Z))
  check(options.draft.dodge == KEY_Z and GameInput.bindings.dodge == KEY_ALT,scene+": edits remain a draft")
  options.cancel()
  check(parent_panel.visible and paused and GameInput.bindings.dodge == KEY_ALT,scene+": cancel preserves controls and returns to pause")
  entry.pressed.emit()
  hud.menu.settings.select("Controls")
  options.start_capture("dodge")
  var mouse := InputEventMouseButton.new()
  mouse.button_index = MOUSE_BUTTON_XBUTTON1
  mouse.pressed = true
  hud.menu.handle_input(mouse)
  options.save()
  check(GameInput.bindings.dodge == -MOUSE_BUTTON_XBUTTON1 and mouse.is_action_pressed("dodge"),scene+": mouse capture saves and updates InputMap")
  if scene == "arena":
   check("Mouse 4" in hud.guide.text,scene+": on-screen guide reflects custom binding")
  else:
   check(options.widgets.dodge.text == "Mouse 4",scene+": Controls panel reflects custom binding")
  GameInput.configure()
  check(GameInput.bindings.dodge == -MOUSE_BUTTON_XBUTTON1,scene+": scene configuration preserves custom bindings")
  entry.pressed.emit()
  hud.menu.settings.select("Controls")
  for button in options.find_children("*","Button",true,false):
   if button.text == "Reset to defaults": button.pressed.emit()
  options.save()
  check(GameInput.bindings == GameInput.DEFAULTS,scene+": restore defaults saves correctly")
  hud.toggle_pause()
  check(not paused,scene+": normal play resumes")
  check(options.categories.get_item_text(options.categories.selected) == "Combat",scene+": resetting bindings preserves navigation preference")
 print("KEYBINDINGS RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
