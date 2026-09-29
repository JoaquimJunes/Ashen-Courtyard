extends "res://tests/fixtures/dodge_stage.gd"
var press_at := -1.0
var ticket: RefCounted
var contact: Dictionary = {}
var elapsed := 0.0
var pressed_at := 0.0
var contacts := 0
var before_contact_pose: Array = []

func record(delta: float) -> void:
	elapsed += delta
	if not p.is_on_floor(): before_contact_pose = p.presentation.capture_pose()
	if press_at < 0 or ticket != null or p.is_on_floor() or p.velocity.y >= 0: return
	var gravity: float = p.forward_dive.gravity_value() if p.forward_dive.active else p.tuning.gravity
	var speed := -p.velocity.y
	var remaining := (sqrt(speed*speed+2.0*gravity*maxf(0,p.position.y))-speed)/gravity
	if remaining <= press_at:
		ticket = p.request_action(&"dodge")
		pressed_at = elapsed

func landed(_kind: StringName, _height: float, _damage: float) -> void:
	contacts += 1
	contact = {"position":p.position,"time":elapsed,"damage":p.landing.last_damage,
		"success":p.landing.roll_succeeded,"stamina":p.stamina,"state":p.state,
		"raw":p.landing.classify(p.motor.impact_down_speed,p.tuning.gravity).fraction*p.max_health}

func drop(height: float = 8.0, window: float = 0.10, stamina: float = 100.0) -> void:
	press_at = -1
	p.controller.intent.movement = Vector3.ZERO
	await prepare()
	p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,height,0)))
	p.stamina = stamina
	p.stamina_wait = 100
	contact.clear()
	contacts = 0
	elapsed = 0
	pressed_at = 0
	ticket = null
	press_at = window

func await_contact() -> void:
	for frame in Engine.physics_ticks_per_second*4:
		if not contact.is_empty(): return
		await settle(1)
	check(false,"Contact occurred within four seconds")

func await_recovery() -> void:
	for frame in Engine.physics_ticks_per_second:
		if p.state == p.State.FREE: return
		await settle(1)
	check(false,"Recovery completed within one second")

func run() -> void:
	GameInput.configure()
	stage = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	p = load("res://scenes/player.tscn").instantiate()
	p.controller.manual = true
	p.combat_enabled = true
	stage.add_child(p)
	p.simulation_stepped.connect(record)
	p.landing.landed.connect(landed)
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for height in [4.5,8.0,12.0]:
			await drop(height)
			await await_contact()
			check(ticket != null and ticket.resolved and ticket.accepted and contact.success,"%s Hz / %.1f m: fresh late press succeeds only at contact" % [rate,height])
			check(contact.state == p.State.DODGE and p.actions.active_definition == p.tuning.landing_roll and p.actions.ground_roll.active and not p.forward_dive.active,"Landing acquires one grounded roll, never another dive launch")
			check(absf(contact.damage-contact.raw*0.5) < 0.001 and absf(p.health-(100-contact.damage)) < 0.001,"Exactly 50 percent fall damage through the shared receiver")
			check(contact.stamina == 75 and p.actions.buffered.is_empty() and p.model.dodge_clip == "roll_forward","Costs 25 once and consumes the press with the forward clip")
			var t: float = contact.time
			var at: Vector3 = contact.position
			await await_recovery()
			check(elapsed-t >= 0.39 and elapsed-t <= 0.4+2.0/rate,"Ground recovery takes 0.40 s at %s Hz (%.3f)" % [rate,elapsed-t])
			check(absf(p.position.z-at.z+3.0) < 0.025 and absf(p.position.y-at.y) < 0.005,"Roll travels 3 m without hopping")
			check(contacts == 1 and p.stamina == 75 and not p.invulnerable and p.actions.active_definition == null,"Impact, payment and ownership do not repeat")
		for window in [0.22,0.35,-1.0]:
			await drop(8,window)
			await await_contact()
			check(not contact.success and contact.state == p.State.LAND and contact.stamina == 100 and is_equal_approx(contact.damage,contact.raw),"%s Hz: early/absent press receives normal recovery and full damage (%s)" % [rate,window])
		await drop(8,0.10,24)
		await await_contact()
		check(not contact.success and ticket.reason == &"insufficient_resources" and contact.stamina == 24 and is_equal_approx(contact.damage,contact.raw),"%s Hz: insufficient stamina spends nothing and uses normal impact" % rate)
		await drop(16)
		await await_contact()
		check(not contact.success and not ticket.accepted and p.dead and p.reactions.active and p.reactions.lethal and contact.damage == 100 and p.stamina == 100,"%s Hz: lethal height cannot be rescued by the timing check" % rate)
		await drop(2.5)
		await await_contact()
		check(not contact.success and contact.state == p.State.FREE and contact.stamina == 100 and ticket.reason == &"landing_not_eligible","%s Hz: soft landings neither roll nor spend" % rate)
		# A dive already owns an action and has paid for takeoff. The contact roll
		# must cleanly replace it and pay its own cost only on success.
		await drop(0.02,-1)
		Shapes.solid(fixtures,Vector3(4,8,4),Vector3(0,4,2),Color.GRAY)
		p.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,8.02,0.5)))
		await settle(6)
		contact.clear()
		contacts = 0
		await ActionTest.start(p,"dodge")
		press_at = 0.1
		ticket = null
		await await_contact()
		check(contact.success and contact.stamina == 50 and p.actions.active_definition.id == &"landing_roll" and not p.forward_dive.active,"%s Hz: cliff dive replaces ownership and pays each action once" % rate)
		check(is_equal_approx(contact.damage,contact.raw*0.5) and p.model.is_processing(),"Dive pose releases to the contact roll and damage is halved")
		var body: int = p.model.rig.bone(p.model.skeleton,"Body")
		check(p.model.dodge_blend_rotations[body].angle_to(before_contact_pose[body][0]) < 0.001,"Contact blend retains the actual diving pose instead of resetting to standing")
	Engine.physics_ticks_per_second = 60
	await drop(8,0.14)
	await await_contact()
	check(contact.success,"A press near the early edge of the 0.15 s window succeeds")
	await drop(8,-1)
	await await_contact()
	var unmitigated: float = p.health
	p.actions.request("dodge",true)
	await settle(14)
	check(not p.landing.roll_succeeded and p.health == unmitigated and p.stamina == 100 and p.state == p.State.LAND,"A post-contact press cannot retroactively reduce damage or skip recovery")
	# The contact-only ability cannot be invoked as a normal grounded action.
	await drop(0.02,-1)
	await settle(6)
	check(p.request_action(&"landing_roll").reason == &"requires_descent","Direct ability requests still require a descending entry")
	await drop(8)
	p.health = 5
	await await_contact()
	check(p.dead and p.reactions.active and contact.success and contact.damage > 5,"A weakened character can still die from the reduced nonlethal-height damage")
	# Facing selects forward, even if the camera is aimed somewhere else.
	for index in 8:
		await drop(4.5)
		p.rotation.y = index*PI/4
		p.rig.rotation.y = p.rotation.y+PI/2
		var forward := -p.global_basis.z
		await await_contact()
		check(p.dodge_dir.dot(forward) > 0.999 and p.model.dodge_clip == "roll_forward","Contact roll follows body forward at heading %s" % index)
	# Echo/holding does not refresh a fresh-input window.
	await drop(8,-1)
	p.controller.manual = false
	var key := InputMap.action_get_events("dodge")[0].duplicate() as InputEventKey
	key.pressed = true
	key.echo = true
	p._unhandled_input(key)
	await await_contact()
	check(not contact.success and p.stamina == 100,"Key repeat cannot arm a landing roll")
	p.controller.manual = true
	# Requests during an incompatible committed attack do not cancel it.
	await drop(4.5,-1)
	await ActionTest.start(p,"heavy")
	await settle(2)
	var blocked: RefCounted = p.request_action(&"dodge")
	check(blocked.resolved and not blocked.accepted and blocked.reason == &"committed","Committed attacks cannot be cancelled into the landing skill")
	# A queued input survives pause but cannot survive reset or a ragdoll hit.
	await drop(8)
	while ticket == null: await settle(1)
	var remaining: float = p.actions.buffer_time
	var position_before := p.position
	paused = true
	await settle(8)
	check(p.actions.buffer_time == remaining and p.position == position_before and not ticket.resolved,"Pause freezes the timing window and trajectory together")
	paused = false
	await await_contact()
	check(contact.success,"Resume uses the same pending timing press")
	await drop(8)
	while ticket == null: await settle(1)
	p.receive_damage(preload("res://features/combat/damage_request.gd").new(1,&"timed_hit"))
	check(p.reactions.active and ticket.resolved and not ticket.accepted and p.actions.buffered.is_empty(),"Accepted falling hit cancels the skill and hands motion to ragdoll")
	check(not p.request_action(&"dodge").accepted and p.stamina == 100,"Ragdoll cannot pay for or queue a landing roll")
	await settle(180)
	check(not p.landing.roll_succeeded,"Ragdoll floor contact cannot use a previous timing input")
	await drop(8)
	await await_contact()
	# Contact's reduced fall damage did not cancel the roll, but a combat hit can.
	p.invulnerable = false
	check(p.receive_damage(preload("res://features/combat/damage_request.gd").new(1,&"roll_hit")) and p.state == p.State.HURT and not p.actions.ground_roll.active,"Ordinary combat damage can interrupt the successful landing roll")
	for reset_phase in ["pending","rolling"]:
		await drop(8)
		if reset_phase == "rolling": await await_contact()
		else:
			while ticket == null: await settle(1)
		p.reset_for_lab(Transform3D.IDENTITY)
		check(p.actions.buffered.is_empty() and p.actions.active_definition == null and not p.landing.roll_succeeded and p.stamina == 100 and p.velocity == Vector3.ZERO,"Reset clears timing, payment and action ownership: "+reset_phase)
	Engine.physics_ticks_per_second = original_rate
	print("LANDING ROLL: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
