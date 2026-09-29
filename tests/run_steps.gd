extends SceneTree
var checks := 0
var failures := 0
var lab: Node3D
var p: CharacterBody3D
var fixtures: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if ok: print("PASS: ",message)
 else:
  failures += 1
  push_error("FAIL: "+message)
func settle(frames: int) -> void:
 for i in frames: await physics_frame
 await process_frame
func prepare(height: float, ceiling: bool = false) -> void:
 for action in ["forward","sprint","left","right"]: Input.action_release(action)
 if is_instance_valid(fixtures):
  fixtures.queue_free()
  await settle(2)
 fixtures = Node3D.new()
 lab.add_child(fixtures)
 Shapes.solid(fixtures,Vector3(3,height,10),Vector3(0,height/2,-4),Color.GRAY)
 if ceiling: Shapes.solid(fixtures,Vector3(3,0.2,8),Vector3(0,2.2,-3),Color.GRAY)
 p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.05,3)))
 await settle(8)
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 for height in [0.25,0.5,0.6,0.61,1.0]:
  for sprint in [false,true]:
   await prepare(height)
   Input.action_press("forward")
   if sprint: Input.action_press("sprint")
   var max_speed := 0.0
   for i in 60:
    await settle(1)
    max_speed = maxf(max_speed,Vector2(p.get_real_velocity().x,p.get_real_velocity().z).length())
   var crossed: bool = p.position.z < 0.6 and p.position.y > height-0.04
   check(crossed == (height <= 0.6),"%.2f m block, sprint %s: height limit respected (position %s)" % [height,sprint,p.position])
   check(max_speed <= (6.5 if sprint else 4.0)+0.02,"Step assist adds no horizontal speed")
 await prepare(0.6,true)
 Input.action_press("forward")
 await settle(60)
 check(p.position.z > 1 and p.position.y < 0.1,"Low ceiling prevents step-up (position %s)" % p.position)
 await prepare(0.6)
 p.reset_for_lab(Transform3D(Basis(Vector3.UP,PI/4),Vector3(1.8,0.05,3)))
 await settle(8)
 Input.action_press("forward")
 await settle(60)
 check(p.position.z < 0.8 and p.position.y > 0.55,"Diagonal approach can step up (position %s)" % p.position)
 await prepare(0.6)
 p.position = Vector3(0,1.4,1.35)
 await settle(1)
 check(not p.try_step_up(Vector3.FORWARD*0.1),"Airborne character cannot use step-up to climb")
 await prepare(0.6)
 p.position.z = 1.32
 p.state = p.State.HEAL
 check(not p.try_step_up(Vector3.FORWARD*0.1),"Healing cannot acquire automatic climbing")
 p.state = p.State.LIGHT
 check(not p.try_step_up(Vector3.FORWARD*0.1),"Attack movement does not acquire automatic climbing")
 p.state = p.State.FREE
 await prepare(0.6)
 Shapes.solid(fixtures,Vector3(3,1.2,6),Vector3(0,0.6,-4),Color.GRAY)
 Shapes.solid(fixtures,Vector3(3,1.8,2),Vector3(0,0.9,-4),Color.GRAY)
 await settle(3)
 Input.action_press("forward")
 await settle(115)
 check(p.position.y > 1.75,"Successive 0.6 m steps can be climbed")
 Input.action_release("forward")
 lab.reset_station()
 check(p.position.y < 0.1 and p.move_velocity.is_zero_approx(),"Station reset clears movement after stepping")
 print("STEPS RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
