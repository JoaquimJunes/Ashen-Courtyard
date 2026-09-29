extends SceneTree
## Real event dispatch covers _input -> GUI -> _unhandled_input ownership.
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ",description)
	else:
		failures += 1
		push_error(description)

func settle() -> void:
	for i in 6: await process_frame

func key(code: int, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)

func click(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	# parse_input_event receives window coordinates; headless windows are 64 px
	# even though the UI uses the project's 1280 x 720 logical viewport.
	event.position = root.get_screen_transform()*at
	event.global_position = event.position
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventMouseButton
	released.pressed = false
	Input.parse_input_event(released)

func use_pause(code: int) -> void:
	GameInput.bindings = GameInput.DEFAULTS.duplicate()
	GameInput.bindings.pause = code
	GameInput.loaded = true
	GameInput.apply()

func check_key_domains() -> void:
	for code in [KEY_SPACE,KEY_A,KEY_Z,KEY_QUOTELEFT,KEY_BRACELEFT,KEY_ASCIITILDE,KEY_YEN,KEY_SECTION,
		KEY_ESCAPE,KEY_TAB,KEY_SHIFT,KEY_CTRL,KEY_ALT,KEY_META,KEY_F1,KEY_F12,KEY_F35,
		KEY_MENU,KEY_HYPER,KEY_HELP,KEY_BACK,KEY_VOLUMEUP,KEY_MEDIAPLAY,KEY_LAUNCHF,
		KEY_GLOBE,KEY_JIS_KANA,KEY_KP_MULTIPLY,KEY_KP_ENTER,KEY_KP_9]:
		check(GameInput.valid_keycode(code),"Godot 4.6.2 physical key remains supported: "+OS.get_keycode_string(code))
	for code in [KEY_NONE,KEY_UNKNOWN,123456,999999999,KEY_SPECIAL,KEY_SPECIAL|0x44,
		KEY_MASK_CTRL|KEY_A,KEY_MASK_SHIFT|KEY_TAB,KEY_MASK_KPAD|KEY_1,KEY_CODE_MASK+1,97]:
		check(not GameInput.valid_keycode(code),"Reject unknown, unnamed or modified keycode: %s" % code)
	for code in [-1,-2,-3,-8,-9]:
		check(GameInput.valid_binding(code),"Supported mouse binding remains valid: %s" % code)
	for bad in [KEY_UNKNOWN,123456,999999999,KEY_MASK_CTRL|KEY_W,-4,0,"invalid"]:
		var config := ConfigFile.new()
		for action in GameInput.DEFAULTS: config.set_value("bindings",action,GameInput.DEFAULTS[action])
		config.set_value("bindings","forward",bad)
		check(config.save("user://input-regressions.cfg") == OK,"Write isolated malformed binding fixture")
		GameInput.load_settings("user://input-regressions.cfg")
		check(GameInput.bindings == GameInput.DEFAULTS,"Malformed binding restores playable defaults: %s" % bad)

func run() -> void:
	check_key_domains()
	CameraPreferences.loaded = true
	for scene in ["arena","movement_lab"]:
		use_pause(KEY_TAB)
		paused = false
		change_scene_to_file("res://scenes/%s.tscn" % scene)
		await settle()
		if scene == "arena": current_scene.boss.frozen = true
		var menu = current_scene.hud.menu
		key(KEY_TAB)
		await settle()
		check(paused and menu.panel.visible and root.gui_get_focus_owner() == menu.resume,scene+": configured Tab opens pause and focuses Resume")
		key(KEY_TAB)
		await settle()
		check(not paused and not menu.panel.visible,scene+": configured Tab resumes before GUI focus navigation and is handled once")
		key(KEY_ESCAPE)
		await settle()
		check(paused and menu.panel.visible,scene+": Escape opens pause after rebinding")
		key(KEY_ESCAPE)
		await settle()
		check(not paused and not menu.panel.visible,scene+": Escape resumes after rebinding")
		use_pause(KEY_ESCAPE)
		key(KEY_ESCAPE)
		await settle()
		key(KEY_TAB)
		await settle()
		check(paused and root.gui_get_focus_owner() != menu.resume,scene+": ordinary Tab still navigates menu focus")
		key(KEY_ESCAPE)
		await settle()
		check(not paused,scene+": default Escape resumes exactly once")
		use_pause(KEY_TAB)
		key(KEY_TAB)
		await settle()
		menu.navigate("Settings")
		menu.settings.select("Controls",false)
		await settle()
		var controls = menu.settings.editors.Controls
		controls.start_capture("dodge")
		key(KEY_TAB)
		await settle()
		check(controls.waiting == "dodge" and menu.current == "Settings" and paused,scene+": capture owns configured Pause and rejects duplicate binding")
		key(KEY_ESCAPE)
		await settle()
		check(controls.waiting.is_empty() and menu.current == "Settings",scene+": Escape cancels capture without backing out")
		controls.start_capture("dodge")
		click(Vector2.ZERO,MOUSE_BUTTON_XBUTTON1)
		await settle()
		check(controls.draft.dodge == -MOUSE_BUTTON_XBUTTON1 and controls.waiting.is_empty(),scene+": mouse binding capture precedes GUI and gameplay")
		key(KEY_TAB)
		await settle()
		check(menu.current == "Confirm" and controls.dirty() and root.gui_get_focus_owner() == menu.keep_editing_button,scene+": configured Pause guards drafts and focuses the modal")
		key(KEY_TAB)
		await settle()
		check(menu.current == "Settings" and controls.dirty(),scene+": configured Pause keeps editing from confirmation")
		use_pause(KEY_P)
		key(KEY_P)
		await settle()
		key(KEY_TAB)
		await settle()
		check(menu.current == "Confirm" and root.gui_get_focus_owner() == menu.apply_changes_button,scene+": ordinary Tab navigates only within confirmation")
		var retro_before: bool = PSXStyle.enabled
		key(KEY_F3)
		key(KEY_F4)
		await settle()
		check(not menu.live_enabled and PSXStyle.enabled == retro_before,scene+": confirmation blocks unhandled diagnostics and display shortcuts")
		key(KEY_ESCAPE)
		await settle()
		check(menu.current == "Settings" and controls.dirty(),scene+": Escape keeps editing from confirmation")
		key(KEY_P)
		await settle()
		click(menu.discard_changes_button.get_global_rect().get_center())
		await settle()
		check(menu.current == "Home" and not controls.dirty() and paused,scene+": pointer can discard drafts through the modal")
		for field in [LineEdit.new(),TextEdit.new()]:
			field.custom_minimum_size = Vector2(200,45)
			menu.pages.Home.add_child(field)
			field.grab_focus()
			await settle()
			key(KEY_P,112)
			await settle()
			check(field.text == "p" and menu.panel.visible and paused,scene+": text entry retains a printable Pause binding in "+field.get_class())
			key(KEY_ESCAPE)
			await settle()
			check(not menu.panel.visible and not paused,scene+": Escape remains available from "+field.get_class())
			field.queue_free()
			key(KEY_P)
			await settle()
		menu.close_menu()
	print("INPUT REGRESSIONS RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
