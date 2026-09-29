extends SceneTree
## Exercise equipment through actual gameplay action/death/reset notifications.
const MODEL = preload("res://scenes/models/ual_mannequin.tscn")
const Damage = preload("res://features/combat/damage_request.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func stowed(equipment: RefCounted) -> bool:
	return equipment.current_sockets.get(&"sword") == &"left_hip" and equipment.current_sockets.get(&"shield") == &"back_shield" and equipment.current_sockets.get(&"bow") == &"back_bow"

func held(equipment: RefCounted) -> bool:
	return equipment.current_sockets.get(&"sword") == &"right_hand" and equipment.current_sockets.get(&"shield") == &"left_hand" and equipment.current_sockets.get(&"bow") == &"back_bow"

func start(actor: CharacterBody3D, action: String) -> bool:
	var ticket: RefCounted = actor.actions.request(action)
	actor.actions.tick()
	return ticket.accepted

func for_rate(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(30,1,30),Vector3(0,-0.5,0),Color.GRAY)
	var session := root.get_node("GameSession")
	var actor: CharacterBody3D = session.create_player(world,session.configure_world(world),true,MODEL)
	actor.controller.manual = true
	for frame in 12: await physics_frame
	await process_frame
	actor.set_physics_process(false)
	actor.model.set_process(false)
	var equipment: RefCounted = actor.model.equipment
	check(equipment != null,"%s Hz: actual UAL player has equipment" % rate)
	if equipment == null:
		world.free()
		return
	equipment.set_layout(&"sword_shield")
	check(held(equipment),"%s Hz: requested sword/shield layout starts held" % rate)
	var animation: AnimationPlayer = actor.model.animation
	animation.play("k_idle")
	animation.seek(0.25,true)
	animation.advance(0)
	var time := animation.current_animation_position
	check(start(actor,"cast") and stowed(equipment),"%s Hz: actual cast start stows both hands synchronously" % rate)
	check(is_equal_approx(animation.current_animation_position,time),"Equipment changes do not restart the animation player")
	equipment.request_hand_release(&"test_traversal")
	actor.actions.cancel(&"test_interrupt")
	check(stowed(equipment) and equipment.desired_layout == &"sword_shield","Cancelling a cast preserves an overlapping traversal release and desired layout")
	equipment.release_hand_release(&"test_traversal")
	check(held(equipment),"Releasing the last reason restores the desired layout")
	actor.health = actor.max_health-10.0
	check(start(actor,"heal") and stowed(equipment),"Actual heal start stows held equipment")
	actor.actions.timer = 2.0
	actor.actions.advance(0)
	actor.actions.finish_if_idle()
	check(held(equipment) and actor.actions.active_definition == null,"Finishing the actual heal restores equipment")

	check(start(actor,"cast"),"Fatal-interruption fixture starts a real cast")
	var before_death: Dictionary = equipment.current_sockets.duplicate()
	var observed_frozen: Array[bool] = []
	actor.damage_applied.connect(func(_request): observed_frozen.append(equipment.death_frozen),CONNECT_ONE_SHOT)
	actor.receive_damage(Damage.new(actor.health+1.0))
	check(actor.dead and observed_frozen == [true],"Equipment freezes before damage/reaction observers cancel actions")
	check(equipment.current_sockets == before_death,"Lethal cast interruption cannot restore held equipment")
	equipment.release_hand_release(&"action_hands")
	equipment.release_hand_release(&"test_traversal")
	check(equipment.death_frozen and equipment.current_sockets == before_death,"Late hand-release callbacks cannot move corpse equipment")
	actor.reset_for_lab(Transform3D.IDENTITY)
	actor.model.set_process(false)
	check(not equipment.death_frozen and equipment.hand_release_reasons.is_empty() and held(equipment),"Player reset clears freezes/reasons and restores the requested layout")
	var socket_count: int = actor.model.skeleton.get_child_count()
	actor.reset_for_lab(Transform3D.IDENTITY)
	check(actor.model.skeleton.get_child_count() == socket_count,"Repeated actor resets do not add sockets or equipment instances")

	check(start(actor,"cast"),"Ragdoll fixture starts a cast")
	actor.reactions.begin(false,true)
	check(actor.reactions.active and equipment.items.size() == 3,"Nonlethal ragdoll retains all carried equipment")
	for item in equipment.items.values():
		check(is_instance_valid(item.visual.get_parent()) and actor.model.skeleton.is_ancestor_of(item.visual),"Ragdoll equipment stays under the character skeleton")
	actor.reset_for_lab(Transform3D.IDENTITY)
	check(not actor.reactions.active and held(equipment),"Reset after ragdoll restores equipment with controlled physics")

	# Retain the observer past scene teardown: it must disconnect before sockets die.
	var bridge: RefCounted = actor.presentation.equipment_bridge
	var actions: RefCounted = actor.actions
	check(start(actor,"cast"),"Scene-exit fixture starts a cast")
	world.queue_free()
	await process_frame
	check(bridge.equipment == null and bridge.actor == null,"Scene exit disconnects equipment observers")
	check(not actions.started.is_connected(bridge.on_started) and not actions.cancelled.is_connected(bridge.on_cancelled),"Retained action lifecycle cannot notify a freed equipment model")

func run() -> void:
	var original_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]: await for_rate(rate)
	Engine.physics_ticks_per_second = original_rate
	print("EQUIPMENT ACTIONS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
