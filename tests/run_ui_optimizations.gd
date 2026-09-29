extends SceneTree
const Candidate = preload("res://features/traversal/ledge_candidate.gd")
class Traversal:
 extends RefCounted
 var candidate: RefCounted
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok: print("PASS: ",description)
 else:
  failures += 1
  push_error(description)
func run() -> void:
 GameInput.configure()
 change_scene_to_file("res://scenes/movement_lab.tscn")
 await process_frame
 await process_frame
 var settings_scene = load("res://features/ui/settings_panel.tscn")
 var settings = settings_scene.instantiate()
 root.add_child(settings)
 settings.open()
 check(settings.selected == "Camera","Fresh Settings opens Camera")
 for tab in ["Controls","Display","Camera"]:
  settings.select(tab)
  check(not settings.dirty(),"Switching tabs never creates unapplied gameplay settings")
  settings.queue_free()
  await process_frame
  settings = settings_scene.instantiate()
  root.add_child(settings)
  settings.open()
  check(settings.selected == tab and settings.editors[tab].visible,"New settings instance restores "+tab+" from disk")
 var config := ConfigFile.new()
 config.set_value("settings","tab",42)
 config.save(settings.VIEW_STATE_PATH)
 settings.queue_free()
 await process_frame
 settings = settings_scene.instantiate()
 root.add_child(settings)
 settings.open()
 check(settings.selected == "Camera","Malformed saved tab falls back to Camera")
 var host := Node3D.new()
 root.add_child(host)
 var view = load("res://features/laboratory/ledge_diagnostics.gd").new()
 host.add_child(view)
 var traversal := Traversal.new()
 var candidate := Candidate.new()
 candidate.can_mantle = true
 candidate.hang = Vector3(0,1,0)
 candidate.lift = Vector3(0,2,0)
 candidate.over = Vector3(0,2,-1)
 candidate.stand = Vector3(0,1.5,-1)
 traversal.candidate = candidate
 view.configure(traversal)
 var original_mesh: Mesh = view.route.mesh
 var initial: int = view.route_rebuilds
 for i in 100: view._process(0.016)
 check(initial == 1 and view.route_rebuilds == initial,"Unchanged path builds once across repeated updates")
 var equivalent := Candidate.new()
 for key in ["hang","lift","over","stand","can_mantle"]: equivalent.set(key,candidate.get(key))
 traversal.candidate = equivalent
 view._process(0.016)
 check(view.route_rebuilds == initial,"Equivalent replacement snapshot reuses path geometry")
 traversal.candidate.stand.x = 1
 view._process(0.016)
 check(view.route_rebuilds == initial+1 and view.route.mesh == original_mesh,"Changed endpoint rebuilds once and reuses mesh resource")
 host.position.x = 3
 view._process(0.016)
 check(view.route_rebuilds == initial+2 and view.route_points[0] == view.route.to_local(candidate.hang),"Parent transform change updates local vertices correctly")
 host.hide()
 traversal.candidate.stand.x = 2
 await process_frame
 check(not view.is_processing() and view.route_rebuilds == initial+2,"Hidden paths do not rebuild")
 host.show()
 check(view.route_rebuilds == initial+3,"Reopening refreshes changes made while hidden")
 traversal.candidate = null
 view._process(0.016)
 check(not view.route.visible,"Missing candidate hides cached path")
 traversal.candidate = candidate
 view._process(0.016)
 check(view.route.visible and view.route.mesh == original_mesh,"Restored candidate displays the correct reusable mesh")
 settings.queue_free()
 host.queue_free()
 original_mesh = null
 settings_scene = null
 await process_frame
 await process_frame
 print("UI OPTIMIZATIONS RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
