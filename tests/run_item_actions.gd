extends SceneTree
## Production character integration at all supported physics rates.
const Driver = preload("res://tests/action_test_driver.gd")
const Damage = preload("res://features/combat/damage_request.gd")
const Catalog = preload("res://features/items/item_catalog.gd")
const DATA = preload("res://features/items/data/catalog.tres")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func settle() -> void:
	await physics_frame
	await process_frame
func reset_actor() -> void:
	actor.reset_for_lab(Transform3D.IDENTITY)
	actor.set_physics_process(true)
	for frame in 4: await settle()
	actor.set_physics_process(false)
	actor.model.set_process(false)
func for_rate(rate: int) -> void:
	Engine.physics_ticks_per_second = rate
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(40,1,40),Vector3(0,-0.5,0),Color.GRAY)
	var session := root.get_node("GameSession")
	actor = session.create_player(world,session.configure_world(world),true)
	actor.controller.manual = true
	await reset_actor()
	var inv: RefCounted = actor.items.inventory
	var equipment: RefCounted = actor.items.equipment
	var visual: RefCounted = actor.model.equipment
	check(inv.entries.size() == 4 and actor.flasks == 3 and equipment.spells.size() == 2 and equipment.gadgets.size() == 1,"Starter inventory/loadout matches current controls")
	var original_sword: StringName = equipment.primary
	var copy: StringName = inv.grant(&"practice_blade")[0]
	check(inv.set_upgrade(copy,1) and equipment.assign(&"primary",copy),"Data-only second blade equips and upgrades")
	check(await Driver.start(actor,&"light"),"Blade reuses the production light action")
	check(is_equal_approx(actor.actions.active_definition.damage,26.4) and actor.actions.active_item.instance_id == copy,"Accepted attack captures its owned copy and upgraded damage")
	check(actor.presentation.sword_attack.current != null,"New item reuses native attack presentation by role")
	check(not equipment.assign(&"primary",original_sword) and not inv.set_upgrade(copy,2),"Active action prevents loadout and upgrade edits")
	var snapshot: RefCounted = actor.actions.active_item
	actor.actions.cancel(&"test")
	check(actor.stamina == 80 and actor.actions.active_item == null and snapshot.ability.damage > 24,"Cancellation retains paid cost and clears live item ownership")
	var pending: RefCounted = actor.request_action(&"heavy")
	check(not pending.resolved and not equipment.assign(&"primary",original_sword) and not inv.set_upgrade(copy,2),"Pending action prevents edits before it commits")
	actor.actions.cancel(&"test")

	var shield: StringName = inv.grant(&"review_shield")[0]
	var bow: StringName = inv.grant(&"review_bow")[0]
	check(equipment.assign(&"off_hand",shield) and equipment.assign(&"primary",bow),"Two-handed bow can coexist with assigned shield")
	check(visual.current_sockets.get(&"bow") == &"left_hand" and visual.current_sockets.get(&"shield") == &"back_shield" and not equipment.off_hand_available(),"Bow draws in both hands while shield stows")
	check((await Driver.result(actor,&"light")).reason == &"unknown_action","Unimplemented bow fixture cannot borrow the sword attack")
	equipment.assign(&"primary",copy)
	check(visual.current_sockets.get(&"sword") == &"right_hand" and visual.current_sockets.get(&"shield") == &"left_hand" and equipment.off_hand_available(),"Switching back restores the assigned shield")
	actor.selected_spell = 0
	check(await Driver.start(actor,&"cast"),"Equipped spell casts")
	check(not equipment.off_hand_available() and visual.current_sockets.get(&"shield") == &"back_shield","Casting releases gameplay hands and visual equipment")
	var cast: Resource = actor.actions.active_definition
	actor.selected_spell = 1
	check(actor.actions.active_definition == cast and cast.damage == 32 and actor.actions.active_item.definition_id == &"azure_bolt","Selection changes cannot rewrite an active cast")
	actor.presentation.mantle.begin(RefCounted.new())
	actor.actions.cancel(&"test")
	check(visual.current_sockets.get(&"shield") == &"back_shield","Overlapping traversal release survives cast cancellation")
	actor.presentation.mantle.finish()
	check(visual.current_sockets.get(&"shield") == &"left_hand","Last hand release restores the shield")

	var potion: StringName = inv.grant(&"practice_potion")[0]
	equipment.assign(&"gadget",potion)
	actor.health = 30
	var old_flasks: int = actor.flasks
	check(await Driver.start(actor,&"heal"),"Existing R action uses the selected potion")
	check(inv.find(potion) == null and equipment.gadgets[0] == &"" and actor.flasks == old_flasks,"Last potion consumes its stack without charging the flask")
	var healing: Resource = actor.actions.active_definition
	actor.actions.timer = healing.windup
	actor.actions.advance(0)
	check(actor.health == 85,"Consumed item snapshot still releases its healing effect")
	actor.actions.advance(0)
	check(actor.health == 85,"Healing releases only once")
	actor.actions.cancel(&"test")
	check(not (await Driver.result(actor,&"heal")).accepted,"Empty gadget slot rejects use")
	equipment.assign(&"gadget",actor.items.flask_id)
	actor.health = 50
	check(await Driver.start(actor,&"heal"),"Flask remains usable through the compatibility input")
	actor.actions.cancel(&"damage")
	check(actor.health == 50 and actor.flasks == old_flasks-1,"Interrupted healing keeps spent inventory charge without applying heal")
	actor.resources.try_spend(0,0,1)
	check(inv.find(actor.items.flask_id).charges == actor.flasks,"Legacy resource costs delegate to the same inventory charge count")

	var record: Dictionary = actor.items.to_record()
	var json_record: Dictionary = JSON.parse_string(JSON.stringify(record))
	check(actor.items.restore(json_record) and actor.items.to_record() == record,"Whole character item record round-trips with stable owned IDs")
	var invalid: Dictionary = record.duplicate(true)
	invalid.equipment.primary = "lost"
	invalid.items[0].upgrade_level = 2
	check(not actor.items.restore(invalid) and actor.items.to_record() == record,"Bad equipment reference cannot partially apply otherwise-valid inventory changes")
	invalid = record.duplicate(true)
	invalid.version = 99
	check(not actor.items.restore(invalid) and actor.items.to_record() == record,"Unsupported save version is rejected atomically")
	check(await Driver.start(actor,&"cast"),"Death fixture starts a spell")
	var frozen: Dictionary = visual.current_sockets.duplicate()
	actor.receive_damage(Damage.new(1000))
	check(actor.dead and visual.death_frozen and visual.current_sockets == frozen and actor.actions.active_item == null,"Death freezes carried visuals and cancels item action ownership")
	await reset_actor()
	check(actor.flasks == 3 and inv.entries.size() == 4 and equipment.off_hand == &"" and equipment.selected_spell == 0,"Retry restores starter ownership, selection and flask charges")
	check(visual.items.size() == 1 and visual.current_sockets.get(&"sword") == &"right_hand","Retry replaces test gear with the starting sword")
	visual.set_layout(&"all_stowed")
	await reset_actor()
	check(visual.current_sockets.get(&"sword") == &"right_hand","Retry restores held gameplay layout after a presentation-only stow")
	var node_count: int = actor.get_tree().get_node_count()
	inv.grant(&"practice_blade",100)
	check(actor.get_tree().get_node_count() == node_count and visual.items.size() == 1,"Unequipped copies add no visuals or processing nodes")
	var actions: RefCounted = actor.actions
	check(await Driver.start(actor,&"cast"),"Unload fixture owns a captured item action")
	world.queue_free()
	await settle()
	check(actions.unloaded and actions.active_item == null and actions.active_definition == null,"Scene exit releases item action ownership")

func new_spell() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(20,1,20),Vector3(0,-0.5,0),Color.GRAY)
	var session := root.get_node("GameSession")
	actor = session.create_player(world,session.configure_world(world),true)
	actor.controller.manual = true
	await reset_actor()
	# Supply a new valid definition without altering any controller or executor.
	var catalog := Catalog.new()
	catalog.definitions.assign(DATA.definitions)
	var nova: Resource = DATA.find(&"azure_bolt").duplicate(true)
	nova.actions = nova.actions.duplicate(true)
	nova.actions.actions[0] = nova.actions.actions[0].duplicate(true)
	nova.actions.actions[0].ability = nova.actions.actions[0].ability.duplicate(true)
	nova.id = &"test_nova"
	nova.display_name = "Test Nova"
	nova.actions.actions[0].ability.id = &"never_hardcoded"
	nova.actions.actions[0].ability.damage = 17
	catalog.definitions.append(nova)
	check(catalog.build(),"New spell definition validates without a controller change")
	actor.items.catalog = catalog
	actor.items.inventory.catalog = catalog
	var spell: StringName = actor.items.inventory.grant(nova.id)[0]
	actor.items.equipment.assign(&"spell",spell,0)
	check(await Driver.start(actor,&"cast"),"Newly named spell uses shared casting execution")
	check(actor.presentation.spell.current != null and actor.model.equipment.current_sockets.get(&"sword") == &"left_hip","Presentation and free-hand behavior use profiles, not spell IDs")
	check(actor.actions.active_definition.id == &"never_hardcoded" and actor.actions.active_definition.damage == 17,"New authored values reach the accepted action")
	actor.actions.timer = actor.actions.active_definition.windup
	actor.actions.advance(0)
	check(actor.services.transients.size() == 1 and actor.services.transients[0].damage == 17,"New spell releases its own projectile payload")
	world.queue_free()
	await settle()

func run() -> void:
	GameInput.configure()
	var original := Engine.physics_ticks_per_second
	for rate in [30,60,120]: await for_rate(rate)
	Engine.physics_ticks_per_second = original
	await new_spell()
	print("ITEM ACTIONS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
