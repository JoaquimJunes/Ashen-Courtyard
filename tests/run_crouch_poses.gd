extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error("FAIL: "+message)
 else: print("PASS: ",message)

func physics_tick(player: CharacterBody3D, delta: float) -> void:
 await physics_frame
 player._physics_process(delta)
 player.pose_driver.evaluate(delta)
 await process_frame

func leg_positions(player: CharacterBody3D) -> Array[Vector3]:
 var result: Array[Vector3] = []
 for role in ["LowerLeg.l", "LowerLeg.r", "Foot.l", "Foot.r"]:
  result.append(player.model.locomotion.world_position(player.model.skeleton, player.model.rig.bone(player.model.skeleton, role))-player.global_position)
 return result

func verify_crouch_stop(player: CharacterBody3D, world: Node3D) -> void:
 var ramp := Shapes.solid(world, Vector3(16, 0.5, 30), Vector3(0, 10, 0), Color.GRAY)
 ramp.rotation.x = deg_to_rad(30)
 var original_rate := Engine.physics_ticks_per_second
 for rate in [30, 60, 120]:
  Engine.physics_ticks_per_second = rate
  var delta: float = 1.0/rate
  for downhill in [false, true]:
   var label := "%s Hz crouch %s" % [rate, "downhill" if downhill else "uphill"]
   var z := -4.0 if downhill else 4.0
   var height := 10.0+0.25/cos(deg_to_rad(30))-z*tan(deg_to_rad(30))
   player.reset_for_lab(Transform3D(Basis(Vector3.UP, PI if downhill else 0), Vector3(0, height+0.08, z)))
   player.controller.intent.movement = Vector3.ZERO
   for frame in 15: await physics_tick(player, delta)
   check(player.is_on_floor() and player.posture.toggle() == &"", label+": crouch begins on actual slope support")
   for frame in int(rate*0.3)+1: await physics_tick(player, delta)
   player.controller.intent.movement = Vector3.BACK if downhill else Vector3.FORWARD
   for frame in rate: await physics_tick(player, delta)
   check(player.model.animation.assigned_animation == "crouch/crouch_walk" and (player.model.animation_profile == null or not player.model.locomotion.contacts.is_empty()), label+": movement uses the supported crouch gait and native terrain contacts")
   var previous := leg_positions(player)
   var transition_before: float = player.presentation.crouch.transition
   var camera_before: float = player.presentation.crouch.camera_weight
   player.controller.intent.movement = Vector3.ZERO
   var peak_speed := 0.0
   var idle_samples := 0
   var clear_idle := true
   for frame in int(rate*0.7)+1:
    await physics_tick(player, delta)
    var current := leg_positions(player)
    for joint in current.size(): peak_speed = maxf(peak_speed, current[joint].distance_to(previous[joint])/delta)
    previous = current
    if player.model.animation.assigned_animation == "crouch/crouch_idle":
     idle_samples += 1
     clear_idle = clear_idle and player.model.locomotion.contacts.is_empty() and player.model.locomotion.anchors.is_empty() and is_zero_approx(player.model.locomotion.pelvis_lowering)
   check(peak_speed < minf(16.0, 0.35/delta), label+": smooth stop joint trajectory (%.3f m/s)" % peak_speed)
   check(idle_samples > rate/3 and clear_idle, label+": every idle frame releases foot locks and pelvis correction")
   check(player.presentation.crouch.gait_exit_pose.is_empty(), label+": stop pose transition completes")
   check(player.presentation.crouch.transition > transition_before and is_equal_approx(player.presentation.crouch.camera_weight, camera_before), label+": stopping does not restart posture or camera transition")
   var displayed: Array = player.presentation.capture_pose()
   var skeleton: Skeleton3D = player.model.skeleton
   var animation: AnimationPlayer = player.model.animation
   skeleton.reset_bone_poses()
   animation.play("crouch/crouch_idle")
   animation.seek(fposmod(player.presentation.crouch.clock, animation.get_animation("crouch/crouch_idle").length), true)
   animation.advance(0)
   # Compare the settled pose with independently sampled idle plus clearance,
   # without walking terrain locks. Source keys remain covered separately.
   player.presentation.crouch.fit_clearance()
   var source_matches := true
   for bone in skeleton.get_bone_count():
    source_matches = source_matches and displayed[bone][0].is_equal_approx(skeleton.get_bone_pose_rotation(bone)) and displayed[bone][1].is_equal_approx(skeleton.get_bone_pose_position(bone))
   check(source_matches, label+": stopped pose converges to clearance-fitted idle without terrain locks")
 Engine.physics_ticks_per_second = original_rate
 ramp.free()

func run() -> void:
 var world := Node3D.new()
 root.add_child(world)
 current_scene = world
 Shapes.solid(world,Vector3(20,1,20),Vector3(0,-0.5,0),Color.GRAY)
 var p: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
 p.controller.manual = true
 world.add_child(p)
 for i in 20: await physics_frame
 await process_frame
 p.set_physics_process(false)
 p.model.set_process(false)
 var model: Node3D = p.model
 var skeleton: Skeleton3D = model.skeleton
 for clip in ["crouch_idle","crouch_walk"]:
  var anim: Animation = model.animation.get_animation("crouch/"+clip)
  var native: bool = model.animation_profile != null and model.animation_profile.is_native("crouch/"+clip)
  var min_height := INF
  var max_height := -INF
  var fitted_height := -INF
  var grounded_fit := true
  var knee_forward := true
  var finite := true
  var stable_idle := true
  var authored_idle := true
  var idle_contacts_cleared := true
  var walking_contacts := true
  var idle_feet: Array[Vector3] = []
  model.reset_locomotion()
  for sample in 33:
   skeleton.reset_bone_poses()
   model.animation.play("crouch/"+clip)
   model.animation.seek(anim.length*sample/32.0,true)
   model.animation.advance(0)
   var sampled: Array[Transform3D] = []
   for bone in skeleton.get_bone_count(): sampled.append(skeleton.get_bone_pose(bone))
   # Only crouch walking receives foot placement. Stationary crouching must
   # preserve its authored leg/foot pose while still fitting the low capsule.
   if native: model.finalize_native_pose(anim.length/32.0,p)
   min_height = minf(min_height,model.dodge_skin_min_height())
   max_height = maxf(max_height,-model.dodge_skin_min_height(Vector3.DOWN))
   for bone in skeleton.get_bone_count():
    finite = finite and skeleton.get_bone_global_pose(bone).is_finite()
    if native and clip == "crouch_idle": authored_idle = authored_idle and sampled[bone].is_equal_approx(skeleton.get_bone_pose(bone))
   if native:
    if clip == "crouch_idle": idle_contacts_cleared = idle_contacts_cleared and model.locomotion.contacts.is_empty() and model.locomotion.anchors.is_empty() and is_zero_approx(model.locomotion.pelvis_lowering)
    else: walking_contacts = walking_contacts and not model.locomotion.contacts.is_empty()
   for side in ["l","r"]:
    # Imported rig faces +Z; knee flexion must remain forward.
    var knee := skeleton.get_bone_global_pose(model.rig.bone(skeleton,"LowerLeg."+side)).origin
    var hip := skeleton.get_bone_global_pose(model.rig.bone(skeleton,"UpperLeg."+side)).origin
    knee_forward = knee_forward and knee.z > hip.z
    if clip == "crouch_idle" and not native:
     var ankle := skeleton.get_bone_global_pose(model.rig.bone(skeleton,"Foot."+side)).origin
     if sample == 0: idle_feet.append(ankle)
     else: stable_idle = stable_idle and ankle.distance_to(idle_feet[0 if side == "l" else 1]) < 0.001
   p.presentation.crouch.fit_clearance()
   fitted_height = maxf(fitted_height,-model.dodge_skin_min_height(Vector3.DOWN))
   grounded_fit = grounded_fit and model.dodge_skin_min_height() > -0.035
  check(finite,clip+": finite full bone transforms")
  if clip == "crouch_idle":
   if native:
    check(authored_idle,"Native stationary crouch preserves every sampled source transform")
    check(idle_contacts_cleared,"Native stationary crouch has no foot targets or pelvis adjustment")
   else: check(stable_idle,"Legacy idle keeps both ankles stationary within 1 mm")
  else:
   check(not native or walking_contacts,"Crouch walking retains terrain contacts")
   check(min_height >= -0.005,clip+": walking clears the ground (%.3f m)" % min_height)
  check(max_height < 1.4,clip+": existing crouch animation stays within its authored 1.4m envelope (%.3f m)" % max_height)
  check(fitted_height <= 0.96 and grounded_fit,clip+": all 33 fitted poses fit the low ceiling with grounded feet (top %.4f, grounded %s)" % [fitted_height,grounded_fit])
  check(knee_forward,clip+": knees bend forward")
  check(anim.loop_mode == Animation.LOOP_LINEAR,clip+": locomotion loop enabled without mutating source")
 for rate in [30,60,120]:
  p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.01,0)))
  check(p.posture.toggle() == &"","Prepare visual transition")
  var previous_height: float = p.motor.capsule.height
  for step in int(rate*0.2)+1:
   p.presentation.crouch.tick(1.0/rate)
   p.model.update_pose(1.0/rate)
   check(p.motor.capsule.height <= previous_height+0.001 and is_equal_approx(p.motor.capsule.height,0.96),"%s Hz: collider stays at 0.96m during visual blend" % rate)
   previous_height = p.motor.capsule.height
   var top: float = -model.dodge_skin_min_height(Vector3.DOWN)
   check(top <= p.posture.definition.crouch_height+0.001,"%s Hz: visual blend fits the lowered ceiling immediately" % rate)
  check(is_equal_approx(p.motor.capsule.height,0.96),"Collision remains 0.96m after visual lowering")
  var before: Array = p.presentation.capture_pose()
  check(p.posture.stand(),"Stand transition validates clearance")
  p.model.update_pose(0)
  var maximum_change := 0.0
  for bone in skeleton.get_bone_count(): maximum_change = maxf(maximum_change,before[bone][1].distance_to(skeleton.get_bone_pose_position(bone)))
  check(maximum_change < 0.001,"Standing transition starts from current pose without snap")
 await verify_crouch_stop(p, world)
 print("CROUCH POSES RESULT: %s checks, %s failures" % [checks,failures])
 quit(1 if failures else 0)
