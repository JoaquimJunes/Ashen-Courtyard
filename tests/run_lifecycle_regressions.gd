extends SceneTree
## Public callbacks must observe committed death and cannot reopen cancellation.
const Damage = preload("res://features/combat/damage_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)

func hit(actor: Combatant, amount: float = 1.0) -> bool:
	return actor.receive_damage(Damage.new(amount,&"",Strike.new()))

func death_callbacks() -> void:
	for observer in ["resource_health","health","damage","damaged"]:
		var victim := Combatant.new()
		victim.health = 1
		victim.resources.health_changed.connect(victim.on_health_changed)
		var deaths := [0]
		var observations: Array[bool] = []
		victim.died.connect(func(): deaths[0] += 1)
		var nested := func():
			observations.append(victim.dead)
			observations.append(hit(victim))
		match observer:
			"resource_health": victim.resources.health_changed.connect(func(_current, _maximum): nested.call(),CONNECT_ONE_SHOT)
			"health": victim.health_changed.connect(func(_current, _maximum): nested.call(),CONNECT_ONE_SHOT)
			"damage": victim.damage_applied.connect(func(_request): nested.call(),CONNECT_ONE_SHOT)
			"damaged": victim.damaged.connect(nested,CONNECT_ONE_SHOT)
		check(hit(victim),observer+": initiating lethal hit is accepted")
		check(observations == [true,false],observer+": callback sees death committed and nested hit rejects")
		check(deaths[0] == 1 and victim.health == 0,observer+": death is published exactly once")
		victim.free()
	# The outer request was nonlethal, but its callback delivers a lethal strike.
	# It must not publish a second death after the nested request finishes.
	for observer in ["health","damage"]:
		var victim := Combatant.new()
		victim.health = 2
		victim.resources.health_changed.connect(victim.on_health_changed)
		var deaths := [0]
		victim.died.connect(func(): deaths[0] += 1)
		if observer == "health": victim.health_changed.connect(func(_current, _maximum): hit(victim),CONNECT_ONE_SHOT)
		else: victim.damage_applied.connect(func(_request): hit(victim),CONNECT_ONE_SHOT)
		hit(victim)
		check(victim.dead and victim.health == 0 and deaths[0] == 1,observer+": nested lethal hit owns the only death event")
		victim.free()

func settle() -> void:
	for frame in 6: await physics_frame
	await process_frame

func cancellation_callbacks(actor: CharacterBody3D) -> void:
	for observer in ["ticket","request","cancelled"]:
		actor.reset_for_lab(Transform3D.IDENTITY)
		var active: RefCounted = actor.actions.request("light")
		actor.actions.tick()
		check(active.accepted,"Cancellation fixture starts an actual attack")
		var pending: RefCounted = actor.actions.request("heavy",true)
		var replacements: Array[RefCounted] = []
		var released_before_notification: Array[bool] = []
		var follow_up := func():
			released_before_notification.append(actor.actions.active_definition == null and actor.actions.strike == null)
			replacements.append(actor.actions.request("cast",true))
			# Nested cancellation and ticking cannot spend resources or reenter teardown.
			actor.actions.cancel(&"nested")
			actor.actions.tick(5.0)
		var request_observer := func(_action, result):
			if result == pending: follow_up.call()
		match observer:
			"ticket": pending.completed.connect(func(_result): follow_up.call(),CONNECT_ONE_SHOT)
			"request": actor.actions.request_completed.connect(request_observer)
			"cancelled": actor.actions.cancelled.connect(func(_id, _reason): follow_up.call(),CONNECT_ONE_SHOT)
		var stamina: float = actor.stamina
		actor.actions.cancel(&"reset")
		if observer == "request": actor.actions.request_completed.disconnect(request_observer)
		check(pending.resolved and pending.reason == &"reset",observer+": original pending request resolves with cancellation reason")
		check(replacements.size() == 1 and replacements[0].resolved and replacements[0].reason == &"cancelling",observer+": callback replacement rejects during cancellation")
		check(released_before_notification == [true],observer+": callbacks observe released action ownership")
		check(actor.actions.pending_result == null and actor.actions.buffered.is_empty() and actor.actions.active_definition == null,observer+": cancellation leaves no action or pending ticket")
		check(actor.stamina == stamina and actor.mana == actor.tuning.mana_max,observer+": rejected replacement and nested tick spend nothing")
		var later: RefCounted = actor.actions.request("heavy")
		actor.actions.tick()
		check(later.accepted,"A fresh request after cancellation returns can start normally")
	actor.actions.cancel(&"fixture")

func forced_reaction_callbacks(actor: CharacterBody3D) -> void:
	for transition in ["hurt","landing"]:
		actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,2,0)))
		actor.motor.launch(3.0)
		actor.actions.request("light")
		actor.actions.tick()
		var pending: RefCounted = actor.actions.request("heavy",true)
		var deaths := [0]
		actor.died.connect(func(): deaths[0] += 1,CONNECT_ONE_SHOT)
		pending.completed.connect(func(_result): hit(actor,999),CONNECT_ONE_SHOT)
		if transition == "hurt": hit(actor)
		else: actor.actions.begin_landing(0.5)
		check(deaths[0] == 1 and actor.dead and actor.state == actor.State.DEAD,transition+": death from a cancellation callback takes priority over the interrupted transition")
		check(actor.actions.active_definition == null and actor.actions.pending_result == null,transition+": callback death releases all action ownership")
		var anchor: Vector3 = actor.reactions.driver.anchor()
		await settle()
		check(actor.reactions.active and actor.reactions.lethal and actor.motor.ragdoll_motion and actor.reactions.driver.anchor().distance_to(anchor) > 0.01,transition+": the corpse retains physical motion after cancellation completes")
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(0,2,0)))
	actor.set_physics_process(true)
	await settle()
	actor.set_physics_process(false)
	actor.motor.launch(3.0)
	actor.actions.request("light")
	actor.actions.tick()
	var pending: RefCounted = actor.actions.request("heavy",true)
	pending.completed.connect(func(_result):
		actor.velocity.y = -1
		hit(actor),CONNECT_ONE_SHOT)
	hit(actor)
	check(not actor.dead and actor.reactions.active and actor.state == actor.State.RAGDOLL and actor.actions.active_definition.id == &"ragdoll","A newer nonlethal forced ragdoll also keeps priority over ordinary hurt")
	actor.reset_for_lab(Transform3D.IDENTITY)
	pending = actor.actions.request("light")
	pending.completed.connect(func(_result): actor.reactions.begin(false,true),CONNECT_ONE_SHOT)
	actor.actions.begin_landing(0.5)
	check(actor.reactions.active and actor.state == actor.State.RAGDOLL and actor.actions.active_definition.id == &"ragdoll","A newer nonlethal forced ragdoll keeps priority over an older landing transition")
	actor.reset_for_lab(Transform3D.IDENTITY)
	for owner in ["actions","player"]:
		pending = actor.actions.request("light")
		pending.completed.connect(func(_result):
			actor.actions.begin_landing(0.5)
			if owner == "player": actor.reactions.begin(false,true)
			else: actor.actions.begin_ragdoll(),CONNECT_ONE_SHOT)
		if owner == "player": actor.reset_for_lab(Transform3D.IDENTITY)
		else: actor.actions.reset()
		check(actor.state == actor.State.FREE and actor.actions.active_definition == null and actor.actions.pending_result == null,owner+": reset callbacks cannot acquire a forced action behind FREE state")
		check(not actor.reactions.active and not actor.motor.ragdoll_motion,owner+": reset finishes with controlled physics after its callbacks")
	actor.reset_for_lab(Transform3D.IDENTITY)

func run() -> void:
	death_callbacks()
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	Shapes.solid(host,Vector3(12,1,12),Vector3(0,-0.5,0),Color.GRAY)
	var session := root.get_node("GameSession")
	var actor = session.create_player(host,session.configure_world(host))
	actor.controller.manual = true
	await settle()
	actor.set_physics_process(false)
	cancellation_callbacks(actor)
	await forced_reaction_callbacks(actor)

	actor.reset_for_lab(Transform3D.IDENTITY)
	var pending: RefCounted = actor.actions.request("light")
	var during_reset: Array[RefCounted] = []
	pending.completed.connect(func(_result): during_reset.append(actor.actions.request("heavy")),CONNECT_ONE_SHOT)
	actor.reset_for_lab(Transform3D.IDENTITY)
	actor.actions.tick()
	check(during_reset.size() == 1 and during_reset[0].reason == &"cancelling","Player reset rejects a request submitted from its cancellation callback")
	check(actor.state == actor.State.FREE and actor.actions.pending_result == null and actor.stamina == actor.tuning.stamina_max,"Player reset clears ownership and restores resources without an orphaned request")

	var deaths := [0]
	var lethal_callback_state: Array[bool] = []
	actor.died.connect(func(): deaths[0] += 1)
	actor.health_changed.connect(func(_current, _maximum):
		lethal_callback_state.append(actor.dead)
		hit(actor),CONNECT_ONE_SHOT)
	hit(actor,actor.health)
	check(lethal_callback_state == [true] and deaths[0] == 1,"Real player health callback cannot deliver a second lethal event")
	check(actor.dead and actor.state == actor.State.DEAD and actor.actions.active_definition == null,"Fatal damage finishes in the death action state")
	actor.reset_for_lab(Transform3D.IDENTITY)
	check(not actor.dead and actor.health == actor.max_health and actor.state == actor.State.FREE,"Explicit player reset starts a fresh living state")
	actor.health = 2
	actor.damage_applied.connect(func(_request): hit(actor),CONNECT_ONE_SHOT)
	hit(actor)
	check(deaths[0] == 2 and actor.dead and actor.state == actor.State.DEAD,"Nonlethal outer player hit cannot overwrite death caused by a nested lethal strike")
	actor.reset_for_lab(Transform3D.IDENTITY)
	# An external observer may retain the action object after its Node unloads.
	pending = actor.actions.request("light")
	var after_unload: Array[RefCounted] = []
	pending.completed.connect(func(_result): after_unload.append(actor.actions.request("heavy")),CONNECT_ONE_SHOT)
	var actions: RefCounted = actor.actions
	actor.queue_free()
	await process_frame
	check(after_unload.size() == 1 and after_unload[0].reason == &"unloaded","Unload callbacks cannot queue another request")
	var late: RefCounted = actions.request("light")
	check(late.resolved and late.reason == &"unloaded" and actions.pending_result == null,"Retained lifecycle rejects requests after its character has been freed")
	host.queue_free()
	await process_frame
	print("LIFECYCLE REGRESSIONS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
