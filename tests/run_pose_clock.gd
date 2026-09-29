extends SceneTree
## Real automatic processing: render cadence cannot drive gameplay poses/sensing.
var checks := 0
var failures := 0
var actor: CharacterBody3D
var observed_ticks := 0
var sampling_ok := true
var order_ok := true
var order_samples := 0
var before_query: Array[Transform3D] = []
var before_frame := -1

class Observer extends Node:
	var callback: Callable
	func _physics_process(_delta: float) -> void: callback.call()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func before_actor() -> void:
	if actor == null: return
	before_frame = Engine.get_physics_frames()
	before_query.assign(actor.hitboxes.query_snapshot())

func after_actor() -> void:
	if actor == null or before_frame != Engine.get_physics_frames(): return
	var poses: Array = actor.hitboxes.query_snapshot()
	order_ok = order_ok and poses == before_query
	order_samples += 1

func observe_pose(_delta: float) -> void:
	observed_ticks += 1
	var driver: RefCounted = actor.pose_driver
	sampling_ok = sampling_ok and driver.sampled_frame == Engine.get_physics_frames()
	var attack: RefCounted = actor.presentation.sword_attack
	if attack.current == null: return
	var animation: AnimationPlayer = actor.model.animation
	var definition: Resource = attack.current
	var recovery: float = animation.get_animation(definition.recovery_clip).length if definition.recovery_clip != &"" else 0.0
	var selected: Dictionary = definition.sample_time(actor.timer,actor.actions.active_definition,animation.get_animation(definition.clip).length,recovery)
	sampling_ok = sampling_ok and animation.assigned_animation == selected.clip and absf(animation.current_animation_position-selected.time) < 0.00001

func ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(100,1,100),Vector3(0,-0.5,0),Color.GRAY)
	var before := Observer.new()
	before.callback = before_actor
	world.add_child(before)
	actor = load("res://scenes/player.tscn").instantiate()
	actor.controller.manual = true
	world.add_child(actor)
	actor.simulation_stepped.connect(observe_pose)
	var after := Observer.new()
	after.callback = after_actor
	world.add_child(after)
	var initial_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		actor.reset_for_lab(Transform3D.IDENTITY)
		# Seed reset is intentionally immediate; compare ordinary completed ticks.
		await ticks(3)
		order_ok = true
		order_samples = 0
		sampling_ok = true
		var initial_ticks: int = actor.pose_driver.pose_ticks
		var initial_observed := observed_ticks
		var request: RefCounted = actor.actions.request("light")
		await ticks(rate)
		check(request.accepted and sampling_ok,"%s Hz: action source times follow physics even when several ticks share a render" % rate)
		check(actor.pose_driver.pose_ticks-initial_ticks == observed_ticks-initial_observed,"%s Hz: exactly one pose evaluation per completed character tick" % rate)
		check(order_samples > 0 and order_ok,"%s Hz: queries before/after target update see identical world snapshots" % rate)
		check(actor.hitboxes.previous_snapshot_frame < actor.hitboxes.snapshot_frame and actor.hitboxes.snapshot_frame == Engine.get_physics_frames(),"%s Hz: both completed hit snapshots carry their physics frame" % rate)
		var clock: float = actor.model.base_clock
		var ticks_before: int = actor.pose_driver.pose_ticks
		var snapshot: Array = actor.hitboxes.query_snapshot().duplicate()
		for alpha in [0.0,0.25,0.75,1.0]: actor.pose_driver.display(alpha)
		check(actor.model.base_clock == clock and actor.pose_driver.pose_ticks == ticks_before and actor.hitboxes.query_snapshot() == snapshot,"Render interpolation changes neither clocks nor hit geometry")
		actor.pose_driver.begin_tick()
		var bone: int = actor.model.rig.bone(actor.model.skeleton,"Hand.r")
		check(actor.model.skeleton.get_bone_pose_rotation(bone).is_equal_approx(actor.pose_driver.current.rotations[bone]),"Next simulation starts from the authoritative pose")
		actor.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(12,0,0)))
		var reset_pose: Array = actor.hitboxes.query_snapshot()
		check(not reset_pose.is_empty() and reset_pose[0].origin.x > 10,"Teleport reseeds both hit snapshots without a trail at the previous position")
		actor.reset_for_lab(Transform3D.IDENTITY)
		await ticks(2)
		var action: RefCounted = actor.actions.request("light")
		await ticks(2)
		actor.take_damage(1,"pose_interrupt_%s" % rate)
		await ticks(2)
		check(action.accepted and actor.presentation.sword_attack.current == null,"Damage releases action pose ownership")
		actor.take_damage(actor.health+1,"pose_death_%s" % rate)
		check(actor.hitboxes.ray(Vector3(0,1,2),Vector3(0,1,-2)).is_empty(),"Dead character cannot serve stale hit geometry")
		actor.reset_for_lab(Transform3D.IDENTITY)
	Engine.physics_ticks_per_second = initial_rate
	actor = null
	world.free()
	print("POSE CLOCK: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
