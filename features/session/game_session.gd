extends Node
## Scene lifecycle belongs here; world hosts own their environment and UI.
signal world_changed(world: Node3D)
var active_world: Node3D
const COMBAT_CONTEXT := &"ashen_combat_context"

func _ready() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args():
		add_child(preload("res://features/session/release_smoke.gd").new())
	elif "--animation-benchmark" in OS.get_cmdline_user_args():
		# Official release templates disable command-line scene path overrides.
		change_world.call_deferred("res://scenes/animation_benchmark.tscn")

func configure_world(world: Node3D) -> Node:
	active_world = world
	world.tree_exiting.connect(func():
		if active_world == world: active_world = null)
	var services: Node = world.get_meta(COMBAT_CONTEXT) if world.has_meta(COMBAT_CONTEXT) else null
	if not is_instance_valid(services) or services.is_queued_for_deletion():
		services = preload("res://features/combat/combat_services.gd").new()
		services.host = world
		world.add_child(services)
		world.set_meta(COMBAT_CONTEXT,services)
	world_changed.emit(world)
	return services

func combat_context_for(character: Node) -> Node:
	# A standalone scene uses the containing world under its viewport. Do not
	# borrow active_world: previews can coexist with a different active scene.
	var lifetime := character
	while lifetime.get_parent() != null and not lifetime.get_parent() is Viewport:
		lifetime = lifetime.get_parent()
	var host: Node = character.get_parent() if lifetime == character else lifetime
	var shared := host == lifetime
	if shared and host.has_meta(COMBAT_CONTEXT):
		var existing: Node = host.get_meta(COMBAT_CONTEXT)
		if is_instance_valid(existing) and not existing.is_queued_for_deletion(): return existing
	var context := preload("res://features/combat/combat_services.gd").new()
	context.host = host
	if shared: host.set_meta(COMBAT_CONTEXT,context)
	# Children may request a context before their world's _ready(). Defer tree
	# insertion until scene assembly finishes; all callers share the same instance.
	host.add_child.call_deferred(context)
	lifetime.tree_exiting.connect(context.queue_free)
	return context

func create_player(host: Node3D, services: Node, combat: bool = true, visual_scene: PackedScene = null) -> CharacterBody3D:
	var player := preload("res://scenes/player.tscn").instantiate()
	if visual_scene != null: player.model_scene = visual_scene
	player.services = services
	player.combat_enabled = combat
	host.add_child(player)
	return player

func set_paused(value: bool) -> void:
	if value:
		for character in get_tree().get_nodes_in_group(Combatant.COMBATANTS):
			if character.get("controller") != null and character.controller.has_method("reset_stance"):
				character.controller.reset_stance()
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED

func change_world(scene: String) -> void:
	set_paused(false)
	get_tree().change_scene_to_file(scene)

func retry() -> void:
	set_paused(false)
	get_tree().reload_current_scene()
