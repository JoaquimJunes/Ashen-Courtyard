extends SceneTree
var checks := 0
var failures := 0
var actor: CharacterBody3D

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	actor = load("res://scenes/player.tscn").instantiate()
	host.add_child(actor)
	actor.controller.manual = true
	actor.set_physics_process(false)
	# Both public completion signals can synchronously submit a newer request.
	for use_ticket_signal in [true,false]:
		actor.reset_for_lab(Transform3D.IDENTITY)
		var notifications: Array[RefCounted] = []
		var observe := func(_action, result): notifications.append(result)
		actor.actions.request_completed.connect(observe)
		var first: RefCounted = actor.actions.request("light")
		var nested: Array[RefCounted] = []
		var follow_up := func(_result): nested.append(actor.actions.request("heavy"))
		var on_request := func(_action, result):
			if result == first: follow_up.call(result)
		if use_ticket_signal: first.completed.connect(follow_up,CONNECT_ONE_SHOT)
		else: actor.actions.request_completed.connect(on_request)
		var outer: RefCounted = actor.actions.request("cast")
		check(first.resolved and first.reason == &"superseded","Original request resolves on supersession")
		check(nested.size() == 1 and actor.actions.pending_result == nested[0],"Newest callback request owns the pending slot")
		check(outer != nested[0] and outer.resolved and outer.reason == &"superseded","Outer caller receives its own superseded ticket")
		actor.actions.tick()
		check(nested[0].resolved and nested[0].accepted,"Nested request resolves on the next action tick")
		check(actor.stamina == 64 and actor.mana == 100,"Only the winning heavy action pays its cost")
		actor.actions.cancel(&"test_cleanup")
		check(notifications.count(first) == 1 and notifications.count(outer) == 1 and notifications.count(nested[0]) == 1,"Every ticket emits exactly one lifecycle notification")
		actor.actions.request_completed.disconnect(observe)
		if not use_ticket_signal: actor.actions.request_completed.disconnect(on_request)
	actor.reset_for_lab(Transform3D.IDENTITY)
	var first: RefCounted = actor.actions.request("light")
	first.completed.connect(func(_result): actor.actions.cancel(&"callback_cancel"),CONNECT_ONE_SHOT)
	var replacement: RefCounted = actor.actions.request("cast")
	check(replacement.resolved and replacement.reason == &"callback_cancel" and actor.actions.pending_result == null,"Cancellation from a completion callback resolves the replacement")
	actor.reset_for_lab(Transform3D.IDENTITY)
	var diagnostics := preload("res://features/ui/character_diagnostics.gd").new()
	actor.add_child(diagnostics)
	diagnostics.configure(actor)
	var notifications: Array[RefCounted] = []
	actor.actions.request_completed.connect(func(_action, result): notifications.append(result))
	var pending: RefCounted = actor.actions.request("heavy")
	var no_descent: RefCounted = actor.actions.request("landing_roll")
	check(no_descent.reason == &"requires_descent" and notifications.count(no_descent) == 1,"Non-descending landing-roll rejection notifies once")
	check(diagnostics.last_request == "landing_roll: requires descent","Diagnostics observes player-specific rejection")
	actor.state = actor.State.HURT
	actor.velocity.y = -1
	var committed: RefCounted = actor.actions.request("dodge")
	check(committed.reason == &"committed" and notifications.count(committed) == 1,"Descending dodge rejection preserves its input action notification")
	actor.state = actor.State.FREE
	actor.movement.attach(preload("res://features/traversal/surface_attachment.gd").new())
	var incompatible: RefCounted = actor.actions.request("light")
	check(incompatible.reason == &"movement_mode" and notifications.count(incompatible) == 1,"Attached action rejection notifies once")
	check(actor.actions.pending_result == pending and not pending.resolved and actor.stamina == 100,"Early rejections preserve the queue and resources")
	actor.actions.cancel(&"cleanup")
	check(notifications.count(no_descent) == 1 and notifications.count(committed) == 1 and notifications.count(incompatible) == 1,"Cleanup never repeats early rejection notifications")
	host.queue_free()
	await process_frame
	print("REQUEST CONTRACTS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
