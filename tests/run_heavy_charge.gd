extends "res://tests/run_light_attack_buffer.gd"

func button(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"light"
	event.pressed = pressed
	if pressed: Input.action_press("light")
	else: Input.action_release("light")
	actor._unhandled_input(event)

func charge(rate: int) -> void:
	Input.action_release("light")
	reset(rate)
	actor.controller.manual = false
	button(true)
	step(int(ceil(0.35*rate)),rate)
	check(actor.actions.heavy_charging(),"%s Hz: hold owns heavy during sword pullback" % rate)

func verify_charge(rate: int) -> void:
	charge(rate)
	var profile: Resource = actor.model.animation_profile.heavy_attack
	var expected: float = profile.strike_start*actor.timer/actor.actions.active_definition.windup
	check(actor.model.animation.assigned_animation == profile.clip and absf(actor.model.animation.current_animation_position-expected) < 0.00001,"%s Hz: charge samples the pre-strike heavy animation" % rate)
	check(actor.services.swings.is_empty(),"Pullback deals no damage")
	var elapsed := float(int(ceil(0.35*rate)))/rate
	while actor.services.swings.is_empty() and elapsed < 1.5:
		step(1,rate)
		elapsed += 1.0/rate
	check(elapsed >= 0.79 and elapsed <= 0.8+2.0/rate,"%s Hz: strike begins after tap detection plus one windup, without a second charge" % rate)
	check(actor.timer >= actor.tuning.heavy.windup and actor.timer < actor.tuning.heavy.windup+1.01/rate,"Automatic strike opens exactly at gameplay windup completion")
	button(false)
	check(actor.state == State.HEAVY,"Releasing after full charge cannot cancel the strike")
	step(rate*2,rate)
	check(starts == [[&"heavy",0]],"A hold produces one heavy and no light follow-up")
	charge(rate)
	var pose: Array = actor.presentation.capture_pose()
	var stamina: float = actor.stamina
	hit()
	check(actor.state == State.FREE and actor.actions.active_definition == null,"Hit during charge cancels action and returns to guard")
	check(actor.stamina == stamina,"Interrupted charge does not refund or charge stamina twice")
	check(actor.presentation.sword_attack.return_pose == pose,"Cancellation captures the displayed pullback for a smooth return")
	actor.model.update_pose(0)
	var same_pose := true
	var after: Array = actor.presentation.capture_pose()
	for bone in pose.size():
		same_pose = same_pose and pose[bone][0].is_equal_approx(after[bone][0]) and pose[bone][1].is_equal_approx(after[bone][1])
	check(same_pose,"Return-to-guard starts at the actual pullback pose without a snap")
	step(rate,rate)
	button(false)
	check(actor.services.swings.is_empty() and starts == [[&"heavy",0]],"Hit prevents damage and a held/released button cannot restart the cancelled charge")
	check(actor.presentation.sword_attack.return_pose.is_empty() and actor.model.animation.assigned_animation == actor.model.idle_clip(),"Return blend finishes in the equipped combat stance")
	charge(rate)
	button(false)
	check(actor.state == State.FREE and not actor.presentation.sword_attack.return_pose.is_empty(),"Early release cancels heavy and starts the return blend")
	step(rate*2,rate)
	check(actor.services.swings.is_empty() and starts == [[&"heavy",0]],"Early release produces neither a heavy strike nor a light attack")
	charge(rate)
	while actor.timer+1.01/rate < actor.tuning.heavy.windup: step(1,rate)
	paused = true
	button(false)
	paused = false
	step(1,rate)
	check(actor.services.swings.is_empty() and actor.state == State.FREE,"A menu release on the final charge frame cancels before the strike clock advances")
	# Ordinary damage rules remain in effect once the strike has started.
	charge(rate)
	while actor.actions.heavy_charging(): step(1,rate)
	hit()
	check(actor.state == State.HURT,"Hits after the charge keep the ordinary hurt reaction")
	button(false)
	charge(rate)
	actor.actions.die()
	actor.dead = true
	step(1,rate)
	check(actor.state == State.DEAD and actor.presentation.sword_attack.return_pose.is_empty(),"Death during charge never blends back into a living combat pose")
	button(false)

func run() -> void:
	GameInput.configure()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(100,1,100),Vector3(0,-0.5,0),Color.GRAY)
	actor = load("res://scenes/player.tscn").instantiate()
	var combat := RecordedCombat.new()
	combat.host = world
	world.add_child(combat)
	actor.services = combat
	actor.controller.manual = true
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.model.set_process(false)
	actor.actions.started.connect(func(id): starts.append([id,actor.combo]))
	await physics_frame
	await process_frame
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		verify_charge(rate)
	Engine.physics_ticks_per_second = original_rate
	Input.action_release("light")
	world.free()
	print("HEAVY CHARGE: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
