extends SceneTree
## One real player, its input boundary, native pose driver and action lifecycle.
const State = preload("res://features/character/character_states.gd").Action
const Intent = preload("res://features/character/character_intent.gd")
const Damage = preload("res://features/combat/damage_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
var starts: Array = []
var clips: Array[StringName] = []

class RecordedCombat extends "res://features/combat/combat_services.gd":
	var swings: Array = []
	func melee(caster: Combatant, amount: float, _strike: RefCounted, _target: Combatant = null) -> void:
		swings.append([caster.serial,caster.timer,amount])

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+description)

func step(frames: int, rate: int) -> void:
	# Drive the complete player simulation with each fixed timestep. Automatic
	# processing is disabled so the renderer cannot add unsampled physics ticks.
	for frame in frames:
		actor._physics_process(1.0/rate)
		actor.pose_driver.evaluate(1.0/rate)
		clips.append(actor.model.animation.assigned_animation)

func reset(rate: int) -> void:
	actor.submit_intent(Intent.new())
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,0.05,0)))
	step(rate/2,rate)
	check(actor.is_on_floor(),"%s Hz: fixture has actual grounded contact" % rate)
	starts.clear()
	clips.clear()
	actor.services.swings.clear()

func start(action: String = "light") -> RefCounted:
	var ticket: RefCounted = actor.actions.request(action)
	actor.actions.tick()
	actor.model.update_pose(0)
	check(ticket.accepted,"Fixture commits "+action)
	return ticket

func hit(amount: float = 1.0) -> void:
	actor.receive_damage(Damage.new(amount,&"",Strike.new()))

func verify_chain(rate: int, press_at: float) -> void:
	reset(rate)
	start()
	var first_serial: int = actor.serial
	var first_cost: float = actor.stamina
	step(int(floor(press_at*rate)),rate)
	var outgoing_time: float = actor.timer
	var queued: RefCounted = actor.actions.request("light",true)
	check(not queued.resolved and actor.stamina == first_cost,"%s Hz: %.2fs press queues without charging" % [rate,press_at])
	for repeat in 5:
		check(actor.actions.request("light",true) == queued,"Repeated clicks share the one pending follow-up ticket")
	var before_transition: Array = []
	var transition_from: Array = []
	var outgoing_observer := func(_id): transition_from.assign(actor.presentation.capture_pose())
	actor.actions.finished.connect(outgoing_observer,CONNECT_ONE_SHOT)
	var waited := 0
	while actor.serial == first_serial and waited < rate:
		before_transition = actor.presentation.capture_pose()
		step(1,rate)
		waited += 1
	check(queued.accepted and actor.serial == first_serial+1 and actor.combo == 1,"%s Hz: queued A transitions into B once" % rate)
	check(actor.stamina == first_cost-actor.tuning.light.stamina_cost,"Follow-up pays exactly once when B starts")
	check(actor.actions.pending_result == null and actor.actions.buffered.is_empty(),"Commit consumes the one follow-up slot")
	var opens: float = actor.tuning.light.windup+actor.tuning.light.active_seconds+actor.tuning.light.chain_after_active
	var elapsed: float = outgoing_time+float(waited)/rate
	check(elapsed >= opens and elapsed < maxf(opens,outgoing_time)+2.0/rate,"%s Hz: chain starts at the window or first tick after a late press" % rate)
	check(transition_from == before_transition and actor.presentation.sword_attack.from_pose == transition_from,"New swing blends from the outgoing displayed pose")
	check(actor.model.animation.assigned_animation == &"combat/sword_regular_b","B is sampled in the transition tick without an idle frame")
	if press_at < opens:
		var uninterrupted := true
		for clip in clips:
			uninterrupted = uninterrupted and clip in [&"combat/sword_regular_a",&"combat/sword_regular_b"]
		check(uninterrupted,"%s Hz: early/mid queue never displays recovery or idle between swings" % rate)
	clips.clear()
	step(rate,rate)
	check(starts == [[&"light",0],[&"light",1]] and actor.state == State.FREE,"Spam before B cannot queue a third swing")
	check(clips.has(&"combat/sword_regular_b_rec"),"Stopping after B plays B's authored recovery")
	var valid_damage := true
	for swing in actor.services.swings:
		valid_damage = valid_damage and swing[1] >= actor.tuning.light.windup and swing[1] < actor.tuning.light.windup+actor.tuning.light.active_seconds and swing[2] == actor.tuning.light.damage
	check(not actor.services.swings.is_empty() and valid_damage,"All chained damage stays inside each authoritative active window")

func verify_stop_and_alternation(rate: int) -> void:
	reset(rate)
	start()
	var duration: float = actor.tuning.light.windup+actor.tuning.light.active_seconds+actor.tuning.light.recovery
	step(int(floor((duration-0.06)*rate)),rate)
	check(actor.state == State.LIGHT and clips.has(&"combat/sword_regular_a_rec"),"An unqueued A stays committed through its recovery")
	step(3+int(ceil(0.06*rate)),rate)
	check(starts.size() == 1 and actor.state == State.FREE,"An unqueued attack finishes without an automatic follow-up")
	reset(rate)
	start()
	for expected_combo in [1,0,1]:
		var queued: RefCounted = actor.actions.request("light",true)
		for frame in rate:
			step(1,rate)
			if queued.resolved: break
		check(queued.accepted and actor.combo == expected_combo,"A fresh press per swing continues A/B alternation")
	step(rate,rate)
	check(starts == [[&"light",0],[&"light",1],[&"light",0],[&"light",1]],"Four fresh attack requests produce exactly A/B/A/B")

func verify_input(rate: int) -> void:
	reset(rate)
	actor.controller.manual = false
	var press := InputEventAction.new()
	press.action = &"light"
	press.pressed = true
	Input.action_press(&"light")
	actor._unhandled_input(press)
	step(rate*2,rate)
	check(starts == [[&"heavy",0]] and actor.actions.pending_result == null,"%s Hz: holding attack charges one heavy without automatic follow-up" % rate)
	Input.action_release(&"light")
	press.pressed = false
	actor._unhandled_input(press)
	step(rate,rate)
	press.pressed = true
	actor._unhandled_input(press)
	press.pressed = false
	actor._unhandled_input(press)
	step(1,rate)
	check(starts.size() == 2,"A later fresh press can start another attack")
	actor.controller.manual = true

func verify_dodge_and_cost(rate: int) -> void:
	reset(rate)
	start()
	var light: RefCounted = actor.actions.request("light",true)
	var dodge: RefCounted = actor.actions.request("dodge",true)
	check(light.resolved and light.reason == &"superseded" and not dodge.resolved,"Dodge replaces the queued light request")
	var paid: float = actor.stamina
	step(int(floor(0.60*rate)),rate)
	check(actor.state == State.LIGHT and not dodge.resolved and actor.stamina == paid,"Dodge survives the short buffer but waits for full attack recovery")
	for frame in rate:
		step(1,rate)
		if dodge.resolved: break
	check(dodge.accepted and actor.state == State.DODGE and starts.size() == 2 and String(starts[1][0]).begins_with("dodge"),"The replacement dodge starts after the attack completes")
	var expected: float = paid-actor.actions.active_definition.stamina_cost
	check(actor.stamina >= expected and actor.stamina <= expected+actor.tuning.stamina_regen/rate+0.00001,"Only the eventual dodge pays a second cost, allowing its free-frame regeneration")
	reset(rate)
	start()
	actor.stamina = actor.tuning.light.stamina_cost-1
	var queued: RefCounted = actor.actions.request("light",true)
	step(int(ceil(0.50*rate)),rate)
	check(queued.resolved and queued.reason == &"insufficient_resources" and actor.state == State.LIGHT,"Insufficient stamina rejects B while A keeps recovering")
	check(actor.stamina == actor.tuning.light.stamina_cost-1 and starts.size() == 1,"Rejected B spends nothing and does not finish A early")
	check(clips.has(&"combat/sword_regular_a_rec"),"Rejected chain displays the outgoing authored recovery")
	step(rate/2,rate)
	check(actor.state == State.FREE and starts.size() == 1,"Rejected chain cannot retry when stamina regenerates")
	reset(rate)
	start("heavy")
	var heavy: RefCounted = actor.actions.request("light",true)
	step(int(ceil(0.30*rate)),rate)
	check(heavy.resolved and heavy.reason == &"expired" and actor.state == State.HEAVY,"Light requests during heavy retain the ordinary short buffer")

func verify_interruptions(rate: int) -> void:
	for interruption in ["damage","death","ragdoll","reset"]:
		reset(rate)
		start()
		var queued: RefCounted = actor.actions.request("light",true)
		match interruption:
			"damage": hit()
			"death": hit(actor.health+1)
			"ragdoll": actor.reactions.begin(false,true)
			"reset": actor.reset_for_lab(Transform3D.IDENTITY)
		check(queued.resolved and not queued.accepted and queued.reason == StringName(interruption),"%s clears the pending light with its cancellation reason" % interruption)
		step(rate,rate)
		check(actor.actions.pending_result == null and starts.count([&"light",1]) == 0,"%s cannot restore a queued swing later" % interruption)

func verify_finished_callbacks(rate: int) -> void:
	for transition in ["death","reset","supersession","cost_change","unload"]:
		reset(rate)
		start()
		var queued: RefCounted = actor.actions.request("light",true)
		var replacement: Array = []
		var on_finished := func(_id):
			match transition:
				"death": hit(actor.health+1)
				"reset": actor.reset_for_lab(Transform3D.IDENTITY)
				"supersession": replacement.append(actor.actions.request("heavy"))
				"cost_change": actor.stamina = 0
				"unload": actor.actions.unload()
		actor.actions.finished.connect(on_finished,CONNECT_ONE_SHOT)
		actor.actions.timer = actor.tuning.light.windup+actor.tuning.light.active_seconds+actor.tuning.light.chain_after_active+0.001
		actor.actions.tick()
		check(queued.resolved and not queued.accepted and starts.count([&"light",1]) == 0,"Finished callback %s prevents stale B commitment" % transition)
		match transition:
			"death": check(actor.dead and actor.state == State.DEAD and actor.stamina == 80,"Death callback cannot charge a posthumous swing")
			"reset": check(actor.state == State.FREE and actor.serial == 0 and actor.stamina == 100,"Reset callback keeps its fresh state and resources")
			"supersession":
				check(queued.reason == &"superseded" and actor.actions.pending_result == replacement[0] and actor.stamina == 80,"Newer finished-callback request owns the slot without stale payment")
				actor.actions.tick()
				check(replacement[0].accepted and actor.state == State.HEAVY and actor.stamina == 44,"Only the callback's replacement commits on its next tick")
			"cost_change": check(queued.reason == &"insufficient_resources" and actor.stamina == 0 and actor.state == State.FREE,"Commit rechecks resources after finished callbacks")
			"unload":
				check(queued.reason == &"unload" and actor.actions.pending_result == null and actor.stamina == 80,"Unload callback releases the slot and blocks payment")
				actor.actions.configure(actor)

func verify_scene_exit() -> void:
	reset(60)
	start()
	var queued: RefCounted = actor.actions.request("light",true)
	var actions: RefCounted = actor.actions
	world.free()
	check(queued.resolved and queued.reason == &"unload" and actions.pending_result == null,"Actual scene exit clears the retained follow-up")
	var late: RefCounted = actions.request("light",true)
	check(late.reason == &"unloaded" and not late.accepted,"A retained lifecycle cannot queue attacks after its actor is freed")

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
	# Register the floor with the physics server before deterministic simulation.
	await physics_frame
	await process_frame
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		for press_at in [0.02,0.25,0.58]: verify_chain(rate,press_at)
		verify_stop_and_alternation(rate)
		verify_input(rate)
		verify_dodge_and_cost(rate)
		verify_interruptions(rate)
		verify_finished_callbacks(rate)
	Engine.physics_ticks_per_second = original_rate
	verify_scene_exit()
	print("LIGHT ATTACK BUFFER: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
