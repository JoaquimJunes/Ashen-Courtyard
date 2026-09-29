extends SceneTree
## Run with an actual Compatibility display too: headless tests cannot compile shaders.
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error(description)
func settle() -> void:
	for i in 3: await process_frame
func shortcut() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F4
	event.pressed = true
	root.push_input(event)
func run() -> void:
	for scene in ["arena", "movement_lab"]:
		paused = false
		change_scene_to_file("res://scenes/%s.tscn" % scene)
		await settle()
		if scene == "arena": current_scene.boss.frozen = true
		var menu = current_scene.hud.menu
		menu.open_menu("Settings")
		menu.settings.select("Display")
		var display = menu.settings.editors.Display
		display.save_path = "user://retro-test.cfg"
		for i in 4:
			var desired: bool = not PSXStyle.enabled
			display.toggle.button_pressed = desired
			check(display.dirty(), scene + ": toggle stages a change")
			display.save()
			await settle()
			check(PSXStyle.enabled == desired and not display.dirty(), scene + ": Apply completes while paused")
			shortcut()
			await settle()
			check(PSXStyle.enabled != desired and not display.dirty(), scene + ": F4 synchronizes paused settings")
		menu.close_menu()
		for i in 4:
			var before: bool = PSXStyle.enabled
			shortcut()
			await settle()
			check(PSXStyle.enabled != before and not paused, scene + ": F4 toggles during gameplay")
	print("RETRO RESULT: %s checks, %s failures" % [checks, failures])
	quit(1 if failures else 0)
