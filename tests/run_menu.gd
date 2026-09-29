extends SceneTree
## Integration coverage: shared navigation, preference drafts and passive diagnostics.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ",description)
	else:
		failures += 1
		push_error(description)
func settle(count: int = 6) -> void:
	for i in count: await process_frame
func escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event
func visible_pages(menu: CanvasLayer) -> int:
	var count := 0
	for page in menu.pages.values():
		if page.is_visible_in_tree(): count += 1
	return count
func run() -> void:
	GameInput.configure()
	var categorized: Array = []
	for group in GameInput.CATEGORIES.values(): categorized.append_array(group)
	check(categorized.size() == GameInput.DEFAULTS.size(),"Every binding belongs to one category")
	for action in GameInput.DEFAULTS:
		check(categorized.count(action) == 1,"Unique category for "+action)
	for scene in ["arena","movement_lab"]:
		CameraPreferences.reset()
		paused = false
		change_scene_to_file("res://scenes/%s.tscn" % scene)
		await settle()
		var actor = current_scene.player
		if scene == "arena": current_scene.boss.frozen = true
		var menu = current_scene.hud.menu
		check(not menu.panel.visible and not menu.live_panel.visible and not menu.geometry.visible,scene+": menu and diagnostics initially hidden")
		check(not menu.is_processing() and not menu.geometry.is_processing() and not menu.geometry.contacts.is_processing(),scene+": closed diagnostics disable visual frame callbacks")
		menu.open_menu("Settings")
		await settle()
		var before: Vector3 = actor.global_position
		await settle(20)
		check(paused and actor.global_position == before,scene+": inspection pauses character simulation")
		check(visible_pages(menu) == 1,scene+": only one content page is visible")
		var camera = menu.settings.editors.Camera
		var controls = menu.settings.editors.Controls
		var display = menu.settings.editors.Display
		camera.save_path = "user://menu-camera.cfg"
		controls.save_path = "user://menu-controls.cfg"
		display.save_path = "user://menu-display.cfg"
		check(not camera.apply_button.visible and not controls.apply_button.visible and not display.apply_button.visible,scene+": unchanged settings hide Apply")
		var original_fov: float = CameraPreferences.values.fov
		camera.widgets.fov.value = 77
		check(camera.apply_button.visible and not camera.apply_button.disabled,scene+": editing reveals enabled Apply")
		camera.widgets.fov.value = original_fov
		check(not camera.apply_button.visible,scene+": reverting the edit hides Apply again")
		camera.widgets.fov.value = 77
		menu.settings.select("Controls")
		check(camera.dirty() and CameraPreferences.values.fov == original_fov,scene+": switching tabs preserves unapplied camera draft")
		for index in controls.categories.item_count:
			controls.categories.select(index)
			controls.show_category()
			var expected: Array = GameInput.CATEGORIES[controls.categories.get_item_text(index)]
			var visible_actions: Array = []
			for action in controls.action_rows:
				if controls.action_rows[action].is_visible_in_tree(): visible_actions.append(action)
			check(visible_actions.size() == expected.size() and controls.empty.visible == expected.is_empty(),scene+": category filters rows and empty state")
		menu.handle_input(escape())
		check(menu.current == "Confirm" and paused,scene+": Escape prompts before discarding any settings draft")
		await settle()
		check(menu.confirmation_overlay.visible and menu.settings.is_visible_in_tree(),scene+": warning overlays the settings page")
		check(menu.confirmation_panel.size.x < menu.panel.size.x and root.get_visible_rect().encloses(menu.confirmation_panel.get_global_rect()),scene+": popup is compact and fits the viewport")
		check(menu.keep_editing_button.get_node(menu.keep_editing_button.focus_next) == menu.apply_changes_button,scene+": keyboard focus stays in popup")
		menu.navigate("Credits")
		check(menu.current == "Confirm" and camera.dirty(),scene+": sidebar cannot bypass the draft guard")
		menu.request_close()
		check(menu.current == "Confirm" and paused,scene+": Resume cannot bypass the draft guard")
		menu.keep_editing_button.pressed.emit()
		check(menu.current == "Settings" and camera.dirty(),scene+": Keep editing retains draft")
		menu.settings.select("Camera")
		camera.apply_button.pressed.emit()
		check(camera.is_visible_in_tree() and paused and CameraPreferences.values.fov == 77 and not camera.dirty(),scene+": Apply saves camera and stays in editor")
		check(not camera.apply_button.visible,scene+": saving hides Apply again")
		camera.reset_button.pressed.emit()
		check(camera.draft == CameraPreferences.DEFAULTS and CameraPreferences.values.fov == 77,scene+": Reset camera stages defaults without applying")
		menu.navigate("Debug")
		check(menu.current == "Confirm",scene+": navigation guards unapplied Reset")
		menu.discard_changes_button.pressed.emit()
		check(menu.current == "Debug" and not camera.dirty(),scene+": Discard continues requested navigation")
		var candidate: RefCounted = actor.traversal.candidate
		var stamina: float = actor.stamina
		for i in 55: menu.diagnostics.record("Fixture event %d" % i)
		check(menu.diagnostics.events.size() == 40,scene+": event history has bounded lifetime")
		menu.debug_snapshot = menu.diagnostics.snapshot()
		menu.select_debug("Events")
		check(menu.debug_text.text.contains("Fixture event 54"),scene+": inspector displays latest events")
		menu.diagnostics.snapshot()
		check(actor.traversal.candidate == candidate and actor.stamina == stamina and actor.global_position == before,scene+": diagnostics do not query contacts or mutate gameplay")
		check(not menu.is_processing() and not menu.geometry.is_processing() and not menu.geometry.contacts.is_processing(),scene+": paused inspector needs no live or unchecked visual updates")
		menu.geometry.hands_enabled = true
		check(menu.geometry.contacts.is_processing(),scene+": enabling hand overlay starts its updates while paused")
		actor.hide()
		check(not menu.geometry.contacts.is_processing(),scene+": hidden ancestor stops contact updates")
		actor.show()
		check(menu.geometry.contacts.is_processing(),scene+": showing ancestor resumes enabled contact overlay")
		menu.geometry.hands_enabled = false
		check(not menu.geometry.contacts.is_processing(),scene+": unchecking hand overlay stops contact updates")
		menu.geometry.capsule_enabled = true
		await settle()
		check(menu.geometry.capsule.visible and menu.geometry.is_processing(),scene+": collision visualization works while paused")
		menu.back()
		check(menu.current == "Settings" and get_root().gui_get_focus_owner() != null,scene+": Back restores previous page and keyboard focus")
		check(not menu.geometry.visible and not menu.geometry.is_processing() and not menu.geometry.contacts.is_processing(),scene+": leaving Debug stops geometry callbacks even with capsule checked")
		menu.settings.select("Controls")
		controls.start_capture("dodge")
		var diagnostics_input := InputEventAction.new()
		diagnostics_input.action = "diagnostics"
		diagnostics_input.pressed = true
		menu.handle_input(diagnostics_input)
		check(not menu.live_enabled,scene+": input capture cannot toggle diagnostics")
		menu.handle_input(escape())
		check(controls.waiting == "" and menu.current == "Settings",scene+": Escape cancels capture without closing settings")
		controls.start_capture("dodge")
		controls.assign(KEY_Z)
		controls.apply_button.pressed.emit()
		check(GameInput.bindings.dodge == KEY_Z and controls.is_visible_in_tree(),scene+": Controls Apply publishes and stays open")
		controls.categories.select(2)
		controls.show_category()
		controls.reset_button.pressed.emit()
		check(controls.draft == GameInput.DEFAULTS and GameInput.bindings.dodge == KEY_Z,scene+": Reset affects all categories but not active bindings")
		controls.apply_button.pressed.emit()
		menu.settings.select("Display")
		var previous_display: bool = PSXStyle.enabled
		display.toggle.button_pressed = not previous_display
		check(PSXStyle.enabled == previous_display and display.dirty(),scene+": Display toggle remains a draft")
		display.apply_button.pressed.emit()
		check(PSXStyle.enabled != previous_display and not display.dirty(),scene+": Display Apply publishes effects preference")
		display.reset_button.pressed.emit()
		check(display.draft,scene+": Display defaults select PS1 effects")
		display.save()
		# Check failed writes do not publish draft values.
		camera.save_path = "user://absent-directory/camera.cfg"
		camera.edit("fov",85)
		camera.save()
		check(CameraPreferences.values.fov == 77 and camera.dirty(),scene+": failed camera save preserves active values")
		camera.discard()
		display.save_path = "user://absent-directory/display.cfg"
		display.toggle.button_pressed = false
		display.save()
		check(PSXStyle.enabled and display.dirty(),scene+": failed display save preserves active effects")
		display.discard()
		await settle()
		check(menu.panel.get_global_rect().encloses(display.apply_button.get_global_rect()) and menu.panel.get_global_rect().encloses(display.reset_button.get_global_rect()),scene+": Apply/Reset fit inside menu")
		menu.close_menu()
		check(not paused and not menu.panel.visible,scene+": closing resumes gameplay")
		if DisplayServer.get_name() != "headless":
			check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,scene+": closing recaptures mouse")
		menu.handle_input(diagnostics_input)
		await settle()
		check(menu.live_panel.visible and not paused and not menu.live_text.text.is_empty(),scene+": diagnostics shortcut shows live overlay during play")
		check(menu.is_processing(),scene+": live text refreshes only while displayed")
		check(menu.diagnostics.compact() == menu.diagnostics.snapshot().compact,scene+": lightweight live text matches inspector state")
		menu.open_menu("Debug")
		check(not menu.is_processing(),scene+": opening inspector stops hidden live text refresh")
		check(paused and not menu.live_panel.visible and menu.current == "Debug",scene+": detailed inspection pauses and replaces live overlay")
		menu.diagnostics.reset()
		check(menu.diagnostics.events.is_empty() and menu.diagnostics.last_request == "None",scene+": resetting diagnostics clears bounded state")
		menu.close_menu()
		if scene == "movement_lab":
			menu.open_menu("Test Grounds")
			menu.navigate("Practice")
			await settle()
			check(root.get_visible_rect().encloses(menu.panel.get_global_rect()),"Movement Practice fits in viewport")
			check(menu.panel.get_global_rect().encloses(menu.back_button.get_global_rect()),"Practice keeps Back visible")
			menu.close_menu()

		menu.open_menu("Settings")
		for editor in [camera,controls,display]:
			editor.restore_defaults()
			editor.discard()
			check(not editor.apply_button.visible,scene+": discarding restores hidden Apply")
		camera.save_path = "user://menu-camera.cfg"
		display.save_path = "user://menu-display.cfg"
		camera.widgets.fov.value = 82
		controls.start_capture("dodge")
		controls.assign(KEY_Z)
		display.toggle.button_pressed = false
		check(controls.apply_button.visible and display.apply_button.visible,scene+": binding and display edits reveal Apply")
		menu.navigate("Credits")
		menu.apply_changes_button.pressed.emit()
		check(menu.current == "Credits" and not menu.settings.dirty() and CameraPreferences.values.fov == 82 and GameInput.bindings.dodge == KEY_Z and not PSXStyle.enabled,scene+": warning Apply saves all changed tabs then continues navigation")
		menu.navigate("Settings")
		camera.widgets.fov.value = 84
		camera.save_path = "user://absent-directory/camera.cfg"
		menu.request_close()
		menu.apply_changes_button.pressed.emit()
		check(menu.current == "Confirm" and paused and camera.dirty() and menu.confirmation_message.text.contains("Could not save"),scene+": failed warning Apply keeps menu open with draft and error")
		camera.save_path = "user://menu-camera.cfg"
		menu.apply_changes_button.pressed.emit()
		check(not paused and not menu.panel.visible and CameraPreferences.values.fov == 84,scene+": successful retry applies then resumes")
		GameInput.save_settings(GameInput.DEFAULTS,"user://menu-controls.cfg")
		PSXStyle.enabled = true
	CameraPreferences.reset()
	print("MENU RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
