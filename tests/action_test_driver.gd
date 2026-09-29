extends RefCounted
## Legacy synchronous test scenarios still run the real request/ongoing-cost tick.
## Production callers queue a ticket and observe its completion signal.
static func result(actor: CharacterBody3D, action: StringName) -> RefCounted:
	var ticket: RefCounted = actor.request_action(action)
	if not ticket.resolved:
		var was_processing := actor.is_physics_processing()
		# Stop after this tick even at 120 Hz with a 60 Hz rendered test loop.
		ticket.completed.connect(func(_result: RefCounted): actor.set_physics_process(false),CONNECT_ONE_SHOT)
		actor.set_physics_process(true)
		while not ticket.resolved:
			await actor.get_tree().physics_frame
			await actor.get_tree().process_frame
		actor.set_physics_process(was_processing)
	return ticket

static func start(actor: CharacterBody3D, action: StringName) -> bool:
	return (await result(actor,action)).accepted
