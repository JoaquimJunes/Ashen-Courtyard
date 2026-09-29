extends SceneTree
const ActionTest = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var lab: Node3D
var p: CharacterBody3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var surfaces: Array = []
var bind_bones: Array[int] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
 checks += 1
 if ok: print("PASS: ",description)
 else:
  failures += 1
  push_error("FAIL: "+description)
func step(frames: int = 1) -> void:
 for i in frames:
  await physics_frame
  await process_frame
  p.pose_driver.evaluate(1.0/60.0)
func clearance(normal: Vector3) -> float:
 var transforms: Array[Transform3D] = []
 for i in mesh.skin.get_bind_count():
  transforms.append(skeleton.global_transform*skeleton.get_bone_global_pose(bind_bones[i])*mesh.skin.get_bind_pose(i))
 var lowest := INF
 for arrays in surfaces:
  var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
  var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
  var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
  for v in vertices.size():
   var point := Vector3.ZERO
   for j in 4:
    var index := v*4+j
    point += (transforms[joints[index]]*vertices[v])*weights[index]
   lowest = minf(lowest,normal.dot(point-p.global_position))
 return lowest
func run() -> void:
 lab = load("res://scenes/movement_lab.tscn").instantiate()
 root.add_child(lab)
 current_scene = lab
 p = lab.player
 p.model.set_process(false)
 skeleton = p.model.skeleton
 mesh = p.model.contact_meshes[0]
 for i in mesh.mesh.get_surface_count(): surfaces.append(mesh.mesh.surface_get_arrays(i))
 for i in mesh.skin.get_bind_count(): bind_bones.append(skeleton.find_bone(mesh.skin.get_bind_name(i)))
 await step(5)
 for mode in ["jog","sprint"]:
  lab.go_to_station(0)
  await step(3)
  Input.action_press("forward")
  if mode == "sprint": Input.action_press("sprint")
  var lowest := INF
  for i in 60:
   await step()
   if i > 12: lowest = minf(lowest,clearance(Vector3.UP))
  check(p.model.animation.current_animation == "running/"+mode,mode+" uses its dedicated clip")
  check(lowest > -0.04,"%s flat-ground skin clearance %.3f m" % [mode,lowest])
  check(p.velocity.length() <= p.tuning.sprint_speed+0.01,"Animation does not increase character speed")
  Input.action_release("forward")
  Input.action_release("sprint")
 for index in 3:
  lab.go_to_station(1)
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(-57+index*6,0.05,46)))
  await step(5)
  Input.action_press("forward")
  Input.action_press("sprint")
  var lowest := INF
  var peak_slope := 0.0
  var pose_finite := true
  for frame in 65:
   await step()
   if p.is_on_floor() and p.get_floor_normal().y < 0.99 and frame > 30:
    lowest = minf(lowest,clearance(p.get_floor_normal()))
    peak_slope = maxf(peak_slope,p.model.locomotion.slope)
   for bone in skeleton.get_bone_count():
    pose_finite = pose_finite and skeleton.get_bone_global_pose(bone).is_finite()
  Input.action_release("forward")
  Input.action_release("sprint")
  check(peak_slope > deg_to_rad((index+1)*10-3),"%d-degree ramp drives slope-aware pose" % [(index+1)*10])
  check(lowest > -0.04,"%d-degree ramp skin clearance %.3f m" % [(index+1)*10,lowest])
  check(pose_finite,"Ramp leg solver remains finite")
 # Descend the steepest ramp to verify slope sign and ground contact reverse.
 lab.go_to_station(1)
 p.reset_for_lab(Transform3D(Basis(Vector3.UP,PI),Vector3(-45,3.6,39)))
 await step(12)
 Input.action_press("forward")
 await step(24)
 var speed_fraction := clampf(Vector2(p.get_real_velocity().x,p.get_real_velocity().z).length()/p.tuning.sprint_speed,0,1)
 var running_pitch: float = -deg_to_rad(p.model.locomotion.tuning.running_lean_degrees)*pow(speed_fraction,1.4)
 check(p.model.locomotion.slope < -0.3 and p.model.locomotion.pitch > running_pitch+0.03,"Descending opposes the forward running lean without forcing a backward bend")
 Input.action_release("forward")
 lab.go_to_station(0)
 await step(5)
 Input.action_press("forward")
 Input.action_press("sprint")
 await step(25)
 Input.action_release("forward")
 Input.action_press("left")
 await step(20)
 var left_bank: float = p.model.locomotion.bank
 check(left_bank > 0.04,"Sharp left turn leans into the turn")
 Input.action_release("left")
 Input.action_press("right")
 await step(35)
 check(p.model.locomotion.bank < -0.04,"S-turn reverses bank instead of retaining the previous lean")
 check(absf(p.model.locomotion.bank) <= deg_to_rad(p.model.locomotion.tuning.turn_lean_degrees*p.model.locomotion.tuning.s_turn_lean_multiplier),"Turn lean remains within its configured limit")
 Input.action_release("right")
 var turn_clearance := INF
 for direction in ["forward","left","forward","right"]:
  Input.action_press(direction)
  for i in 12:
   await step()
   turn_clearance = minf(turn_clearance,clearance(Vector3.UP))
  Input.action_release(direction)
 check(turn_clearance > -0.04,"Repeated S-turns preserve ground clearance (%.3f m)" % turn_clearance)
 Input.action_release("sprint")
 await step(60)
 check(absf(p.model.locomotion.bank) < 0.01 and absf(p.model.locomotion.pitch) < 0.01,"Stopping settles to a neutral pose")
 check(p.model.animation.current_animation == p.model.idle_clip(),"Stopped character returns to its equipment-appropriate idle")
 p.model.set_process(true)
 lab.hud.toggle_pause()
 var pose := skeleton.get_bone_pose_rotation(p.model.rig.bone(skeleton,"Body"))
 for i in 4: await process_frame
 check(pose.is_equal_approx(skeleton.get_bone_pose_rotation(p.model.rig.bone(skeleton,"Body"))),"Pause freezes the running pose")
 lab.hud.toggle_pause()
 p.model.set_process(false)
 lab.reset_station()
 check(p.model.locomotion.anchors.is_empty() and is_zero_approx(p.model.locomotion.bank),"Station reset clears planted feet and turn history")
 await step(8)
 (await ActionTest.start(p,"dodge"))
 await step(4)
 check(not p.model.locomotion.initialized and p.model.animation.current_animation.begins_with("dodge/"),"Dodge takes full control of the pose")
 lab.reset_station()
 p.combat_enabled = true
 (await ActionTest.start(p,"light"))
 await step(3)
 check(not p.model.locomotion.initialized,"Attacking suspends running corrections")
 print("RUNNING RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
