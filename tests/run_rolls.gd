extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var mesh: MeshInstance3D
var skeleton: Skeleton3D
var surfaces: Array = []
var bind_bones: Array[int] = []
func _initialize() -> void:
 call_deferred("run")
func check(condition: bool, description: String) -> void:
 checks += 1
 if condition: print("PASS: "+description)
 else:
  failures += 1
  push_error("FAIL: "+description)
func ground_player(p: CharacterBody3D) -> void:
 # Gameplay dodge now requires floor contact; pose sampling disables physics.
 p.position = Vector3.ZERO
 p.velocity = Vector3(0,-1,0)
 p.move_and_slide()
func bounds() -> Vector2:
 var transforms: Array[Transform3D] = []
 for i in mesh.skin.get_bind_count():
  transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bind_bones[i])*mesh.skin.get_bind_pose(i))
 var result := Vector2(INF,-INF)
 for arrays in surfaces:
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
  var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
  for v in vertices.size():
   var point := Vector3.ZERO
   for j in 4:
    var index := v*4+j
    point += (transforms[joints[index]]*vertices[v])*weights[index]
   result.x = minf(result.x,point.y)
   result.y = maxf(result.y,point.y)
 return result
func run() -> void:
 var arena = load("res://scenes/arena.tscn").instantiate()
 root.add_child(arena)
 current_scene = arena
 var p = arena.player
 p.set_physics_process(false)
 arena.boss.set_physics_process(false)
 p.rig.set_physics_process(false)
 p.position = Vector3.ZERO
 p.rotation = Vector3.ZERO
 p.model.set_process(false)
 skeleton = p.model.skeleton
 mesh = p.model.contact_meshes[0]
 for i in mesh.mesh.get_surface_count(): surfaces.append(mesh.mesh.surface_get_arrays(i))
 for i in mesh.skin.get_bind_count(): bind_bones.append(skeleton.find_bone(mesh.skin.get_bind_name(i)))
 var body: int = p.model.rig.bone(skeleton,"Body")
 var midpoints: Dictionary = {}
 for clip in ["roll_forward","roll_left","roll_right","roll_back"]:
  p.model.dodging = true
  p.model.dodge_clip = clip
  var low := INF
  var high := -INF
  for sample in 241:
   p.model.dodge_progress = float(sample)/240
   p.model.update_pose(0)
   var height := bounds()
   low = minf(low,height.x)
   high = maxf(high,height.y)
   if sample == 60: midpoints[clip] = skeleton.get_bone_pose_rotation(body)
  check(low >= -0.005,"%s stays above ground, including interpolated poses (min %.4f m)" % [clip,low])
  check(high < 2.8,"%s remains within a plausible character height (max %.2f m)" % [clip,high])
  check(p.model.rotation.is_zero_approx(),"%s never rotates the visual root around its feet" % clip)
 check(midpoints.roll_forward.angle_to(midpoints.roll_left) > 1.0,"Forward and left rolls have different torso rotation")
 check(midpoints.roll_left.angle_to(midpoints.roll_right) > 1.0,"Left and right rolls lean toward opposite shoulders")
 # Allow newly created world colliders to register before establishing contact.
 await physics_frame
 await physics_frame
 # Exercise actual gameplay selection and preserve the original resource/timing rules.
 for action in {"forward":"roll_forward","left":"roll_left","right":"roll_right","back":"roll_back"}:
  p.actions.cancel(&"test_reset")
  ground_player(p)
  p.state = p.State.FREE
  p.stamina = 100
  p.rig.rotation = Vector3.ZERO
  Input.action_press(action)
  var started: bool = (await ActionTest.start(p,"dodge"))
  Input.action_release(action)
  check(started and ((p.forward_dive.active and p.forward_dive.pose != null) if action == "forward" else p.model.dodge_clip == {"forward":"roll_forward","left":"roll_left","right":"roll_right","back":"roll_back"}[action]),"%s input selects its own animation path" % action)
  check(p.stamina == 100-p.actions.active_definition.stamina_cost,"%s spends the existing dodge cost once" % action)
 p.actions.cancel(&"test_reset")
 p.stamina = 100
 ground_player(p)
 (await ActionTest.start(p,"dodge"))
 check(p.forward_dive.active,"Standing dodge selects the shared forward dive")
 p.actions.cancel(&"test_reset")
 p.model.set_process(false)
 p.stamina = 100
 ground_player(p)
 Input.action_press("back")
 (await ActionTest.start(p,"dodge"))
 Input.action_release("back")
 p.timer = 0.15
 p._physics_process(0.001)
 p.model.update_pose(0)
 check(p.invulnerable,"Imported animation preserves the invulnerability window")
 p.timer = 1.1
 p.position.y = 0
 p.velocity = Vector3(0,-1,0)
 p.move_and_slide()
 p.dodge_phase = p.DodgePhase.GROUND_ROLL
 p.dodge_ground_time = p.actions.active_definition.ground_duration
 p._physics_process(0.001)
 p.model.update_pose(0.016)
 check(p.state == p.State.FREE and not p.model.dodging and not p.invulnerable,"Roll completion restores locomotion and ends immunity")
 # The animation now blends out instead of snapping upright on the last tick.
 p.model.update_pose(p.model.locomotion.tuning.transition_seconds+0.01)
 var recovered := bounds()
 check(recovered.x >= p.position.y-0.05 and recovered.y-p.position.y > 1.5,"Locomotion restores upright posture after rolling")
 p.state = p.State.FREE
 p.stamina = 100
 ground_player(p)
 (await ActionTest.start(p,"dodge"))
 p.take_damage(1,"interrupt_roll_start")
 p.model.update_pose(0.016)
 check(not p.model.dodging and p.state == p.State.HURT,"Damage before immunity interrupts the roll pose")
 arena.hud.restart()
 await process_frame
 await physics_frame
 arena = current_scene
 check(not arena.player.model.dodging and arena.player.model.rotation.is_zero_approx(),"Retry clears all roll animation state")
 print("ROLL RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
