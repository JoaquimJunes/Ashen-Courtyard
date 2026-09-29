extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok: print("PASS: ",description)
 else:
  failures += 1
  push_error(description)
func settle(frames: int = 8) -> void:
 for i in frames: await physics_frame
 await process_frame
func shortcut() -> void:
 var event := InputEventKey.new()
 event.physical_keycode = KEY_F4
 event.pressed = true
 root.push_input(event)
func run() -> void:
 CameraPreferences.loaded = true
 for scene in ["movement_lab","arena"]:
  paused = false
  CameraPreferences.reset()
  change_scene_to_file("res://scenes/%s.tscn" % scene)
  await settle()
  if scene == "arena": current_scene.boss.frozen = true
  var actor = current_scene.player
  var menu = current_scene.hud.menu
  actor.set_physics_process(false)
  actor.actions.cancel(&"fixture")
  actor.combat_enabled = false
  menu.diagnostics.reset()
  var notifications: Array = []
  actor.actions.request_completed.connect(func(action, result): notifications.append({"action":action,"result":result}))
  var stamina: float = actor.stamina
  var mana: float = actor.mana
  var queued: RefCounted = actor.actions.request("jump")
  var timer: float = actor.actions.buffer_time
  var rejected: RefCounted = actor.actions.request("light",true)
  check(rejected.resolved and not rejected.accepted and rejected.reason == &"disabled",scene+": disabled attack rejects immediately")
  check(notifications.size() == 1 and notifications[0].result == rejected and notifications[0].action == &"light",scene+": early rejection emits exactly once with the returned result")
  check(menu.diagnostics.last_request == "light: disabled" and menu.diagnostics.events.size() == 1,scene+": debug history receives the rejection reason")
  check(actor.actions.pending_result == queued and not queued.resolved and actor.actions.buffer_time == timer,scene+": rejected action preserves an existing buffered request")
  check(actor.stamina == stamina and actor.mana == mana,scene+": rejection spends no resources")
  var unknown: RefCounted = actor.actions.request("nonexistent")
  check(unknown.reason == &"unknown_action" and notifications.size() == 2 and notifications[1].result == unknown,scene+": unknown actions also notify once")
  actor.actions.cancel(&"fixture")
  check(notifications.size() == 3 and notifications[2].action == &"jump",scene+": subsequent cancellation does not re-emit rejected actions")
  menu.open_menu("Debug")
  menu.select_debug("Camera")
  check(menu.debug_text.text.contains("65°"),scene+": inspector captures initial camera FOV")
  menu.navigate("Settings")
  menu.settings.select("Camera")
  var camera_editor = menu.settings.editors.Camera
  camera_editor.save_path = "user://bug-fix-camera.cfg"
  camera_editor.widgets.fov.value = 83
  camera_editor.save()
  await settle(20)
  menu.back()
  check(menu.current == "Debug" and menu.debug_text.text.contains("83°") and is_equal_approx(actor.camera.fov,83),scene+": Back refreshes inspector after applying camera settings")
  check(menu.debug_buttons.Camera.has_focus(),scene+": refreshed inspector restores previous keyboard focus")
  menu.navigate("Settings")
  menu.settings.select("Display")
  var display = menu.settings.editors.Display
  var previous: bool = PSXStyle.enabled
  shortcut()
  check(PSXStyle.enabled != previous and display.toggle.button_pressed == PSXStyle.enabled,scene+": real F4 input updates effects and visible checkbox")
  check(not display.dirty() and not display.apply_button.visible,scene+": shortcut creates no phantom unsaved draft")
  menu.back()
  check(menu.current == "Debug" and not menu.confirmation_overlay.visible,scene+": Back after F4 shows no false warning")
  menu.navigate("Settings")
  menu.settings.select("Camera")
  camera_editor.widgets.fov.value = 79
  shortcut()
  check(camera_editor.dirty() and camera_editor.draft.fov == 79 and not display.dirty(),scene+": F4 syncs hidden Display tab without discarding Camera edits")
  menu.settings.select("Display")
  check(display.toggle.button_pressed == PSXStyle.enabled,scene+": reopened Display tab reflects shortcut")
  camera_editor.discard()
  display.toggle.button_pressed = not PSXStyle.enabled
  var pending: bool = display.draft
  shortcut()
  check(display.draft == pending and PSXStyle.enabled == pending and not display.apply_button.visible,scene+": shortcut matching an existing draft clears stale Apply state")
  menu.close_menu()
  shortcut()
  check(display.toggle.button_pressed == PSXStyle.enabled,scene+": closed editor observes effects changes without per-frame polling")
 CameraPreferences.reset()
 print("BUG FIXES RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
