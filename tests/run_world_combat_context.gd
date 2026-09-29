extends SceneTree
const Aim = preload("res://features/combat/aim_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)
func settle() -> void:
	await physics_frame
	await process_frame

func run() -> void:
	# Assemble children before entering the tree, as an authored scene would.
	var host := Node3D.new()
	var caster: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	var other: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	caster.controller.manual = true
	other.controller.manual = true
	host.add_child(caster)
	host.add_child(other)
	root.add_child(host)
	current_scene = host
	caster.set_physics_process(false)
	other.set_physics_process(false)
	other.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(10,0,0)))
	await settle()
	var context: Node = caster.services
	check(context == other.services and context.get_parent() == host,"Standalone characters share a containing-world context")
	check(root.get_node("GameSession").configure_world(host) == context,"Explicit world registration reuses a context created during child assembly")
	context.cast(caster,caster.tuning.bolt,Aim.new(Vector3(0,1,0),Vector3(0,1,-20)),Strike.new())
	var bolt: Node3D = context.transients[0]
	var origin := bolt.global_position
	check(bolt.get_parent() == host,"Released projectile is parented to the world")
	caster.queue_free()
	await settle()
	check(is_instance_valid(bolt) and is_instance_valid(context),"Caster removal preserves projectile and combat context")
	if is_instance_valid(bolt): check(bolt.global_position.z < origin.z,"Released projectile continues moving without its caster")
	if not is_instance_valid(context): context = other.services
	# Let the orphaned projectile reach a real receiver.
	var victim := Combatant.new()
	victim.services = context
	host.add_child(victim)
	victim.setup(100,preload("res://features/character/data/warden_body.tres"))
	victim.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0,-3)))
	for i in 20: await settle()
	check(victim.health == 100-other.tuning.bolt.damage,"Projectile still deals damage after caster removal")
	context.cast(other,other.tuning.bolt,Aim.new(Vector3(10,1,0),Vector3(10,1,-30)),Strike.new())
	var remaining: Node = context.transients[-1]
	host.queue_free()
	await settle()
	check(not is_instance_valid(remaining) and not is_instance_valid(context),"World unload cleans up remaining projectiles and services")
	# Explicit composition still takes precedence over the fallback.
	var injected_world := Node3D.new()
	root.add_child(injected_world)
	current_scene = injected_world
	var injected: Node = root.get_node("GameSession").configure_world(injected_world)
	var actor = root.get_node("GameSession").create_player(injected_world,injected)
	check(actor.services == injected,"Injected combat context is preserved")
	injected_world.queue_free()
	await settle()
	# F6 on the character scene itself has no containing Node3D world.
	var preview: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	preview.set_physics_process(false)
	await settle()
	var preview_context: Node = preview.services
	preview_context.cast(preview,preview.tuning.bolt,Aim.new(Vector3(0,1,0),Vector3(0,1,-30)),Strike.new())
	var preview_bolt: Node = preview_context.transients[0]
	preview.queue_free()
	await settle()
	await settle()
	check(not is_instance_valid(preview_context) and not is_instance_valid(preview_bolt),"Root-character preview teardown leaves no viewport-owned context or projectile")
	var short_world := Node3D.new()
	var short_actor: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	short_world.add_child(short_actor)
	root.add_child(short_world)
	var pending_context: Node = short_actor.services
	short_world.free()
	await settle()
	check(not is_instance_valid(pending_context),"World unload before deferred insertion does not leak its pending context")
	print("WORLD COMBAT CONTEXT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
