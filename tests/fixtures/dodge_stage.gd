extends SceneTree
## Shared flat-ground fixture; tests always exercise the production character.
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var stage: Node3D
var p: CharacterBody3D
var fixtures: Node3D
func _initialize() -> void: run.call_deferred()
func run() -> void: pass
func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ",message)
	else:
		failures += 1
		push_error("FAIL: "+message)
func settle(frames: int) -> void:
	for i in frames: await physics_frame
	await process_frame
func prepare(start: Vector3 = Vector3(0,0.05,0)) -> void:
	p.set_physics_process(false)
	if is_instance_valid(fixtures):
		fixtures.queue_free()
		await settle(2)
	fixtures = Node3D.new()
	stage.add_child(fixtures)
	Shapes.solid(fixtures,Vector3(30,1,30),Vector3(0,-0.5,0),Color.GRAY)
	p.reset_for_lab(Transform3D(Basis.IDENTITY,start))
	p.set_physics_process(true)
	await settle(10)
