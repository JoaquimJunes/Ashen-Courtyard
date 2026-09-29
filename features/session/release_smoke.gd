extends Node
## Opt-in packaged-game check; uses production scenes, input intents and actions.
const ARENA := "res://scenes/arena.tscn"
const LAB := "res://scenes/movement_lab.tscn"
const UAL_REVIEW := "res://scenes/ual_validation.tscn"
const Intent = preload("res://features/character/character_intent.gd")
var failed := false

func _ready() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> bool:
	if condition: return true
	failed = true
	push_error("RELEASE SMOKE: FAIL: "+message)
	get_tree().quit(1)
	return false

func frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func wait_world(path: String) -> Node3D:
	for index in 180:
		var world: Node3D = get_parent().active_world
		if is_instance_valid(world) and world == get_tree().current_scene and world.is_node_ready() and world.scene_file_path == path:
			return world
		await frames(1)
	check(false,"Scene did not become ready: "+path)
	return null

func check_character(actor: CharacterBody3D, label: String) -> bool:
	if not check(is_instance_valid(actor) and actor.is_node_ready(),label+" is missing or unready"): return false
	if not check(not actor.dead and actor.health > 0,label+" unexpectedly died"): return false
	if not check(is_instance_valid(actor.model) and actor.model.is_node_ready(),label+" model did not load"): return false
	if not check(is_instance_valid(actor.model.skeleton) and actor.model.skeleton.get_bone_count() > 0,label+" skeleton did not load"): return false
	if not check(not actor.model.contact_meshes.is_empty(),label+" skinned mesh did not load"): return false
	if not check(is_instance_valid(actor.model.animation),label+" animation player did not load"): return false
	# These clips are loaded through constructed paths, so export dependency
	# discovery alone cannot establish that they were included in the package.
	for clip in ["running/jog","running/sprint","jump/jump_start","jump/jump_air","jump/jump_land","crouch/crouch_idle","crouch/crouch_walk","dodge/roll_forward","dodge/roll_left","dodge/roll_right","dodge/roll_back"]:
		if not check(actor.model.animation.has_animation(clip),label+" missing packaged animation: "+clip): return false
	if actor.model.rig.identifier == &"ual1_65_v1":
		if not check(actor.model.animation.has_animation("crawling/crawl"),label+" missing packaged Mixamo crawl"): return false
		for clip in ["sword_regular_a","sword_regular_b","sword_regular_a_rec","sword_regular_b_rec"]:
			if not check(actor.model.animation.has_animation("combat/"+clip),label+" missing packaged native sword animation: "+clip): return false
		for clip in ["combat/sword_idle","combat/sword_heavy","casting/spell_enter","casting/spell_idle","casting/spell_shoot","casting/spell_exit","traversal/climb_up_1m_rm","swimming/swim_idle","swimming/swim_forward"]:
			if not check(actor.model.animation.has_animation(clip),label+" missing packaged native action: "+clip): return false
	return true

func check_world(world: Node3D, courtyard: bool) -> bool:
	if not check(is_instance_valid(world),"World did not load"): return false
	if not check_character(world.player,"Player"): return false
	if not check(world.player.model.rig.identifier == &"ual1_65_v1","Player did not load the approved UAL model"): return false
	if not check(is_instance_valid(world.hud) and world.hud.is_node_ready(),"HUD did not load"): return false
	if not check(is_instance_valid(world.hud.menu) and world.hud.menu.is_node_ready(),"Shared menu did not load"): return false
	if courtyard:
		if not check_character(world.boss,"Warden"): return false
		if not check(world.hud.player == world.player and world.hud.boss == world.boss,"Encounter HUD is not bound to its characters"): return false
		world.boss.frozen = true
	else:
		if not check(world.stations.size() == 9 and is_instance_valid(world.practice),"Laboratory station or practice scenes are missing"): return false
	return true

func action(actor: CharacterBody3D, id: StringName) -> bool:
	var ticket: RefCounted = actor.request_action(id)
	for index in 30:
		if ticket.resolved: break
		await frames(1)
	if not check(ticket.resolved and ticket.accepted,"Action %s rejected or timed out: %s" % [id,ticket.reason]): return false
	return check(not actor.dead,"Player died while starting "+String(id))

func exercise_player(world: Node3D, courtyard: bool) -> bool:
	var actor: CharacterBody3D = world.player
	var intent := Intent.new()
	actor.submit_intent(intent)
	await frames(12)
	if not check(actor.is_on_floor(),"Player did not settle on the world floor"): return false
	var origin := actor.global_position
	intent.movement = Vector3.RIGHT
	await frames(12)
	intent.movement = Vector3.ZERO
	if not check(actor.global_position.distance_to(origin) > 0.05,"Movement intent did not move the player"): return false
	await frames(20)
	if not await action(actor,&"crouch"): return false
	await frames(20)
	if not check(actor.posture.crouched,"Crouch did not lower player posture"): return false
	if not await action(actor,&"crouch"): return false
	if not check(not actor.posture.crouched,"Standing did not restore player posture"): return false
	if not await action(actor,&"crawl"): return false
	intent.movement = Vector3.RIGHT
	await frames(25)
	intent.movement = Vector3.ZERO
	if not check(actor.crawling.active and actor.motor.crawling_posture and actor.model.animation.assigned_animation == "crawling/crawl","Packaged crawl did not retain posture and animation"): return false
	await frames(10)
	if not await action(actor,&"crouch"): return false
	if not await action(actor,&"crouch"): return false
	var feet_y := actor.global_position.y
	if not await action(actor,&"jump"): return false
	var rose := false
	var landed := false
	for index in 180:
		await frames(1)
		rose = rose or actor.global_position.y > feet_y+0.10
		if rose and actor.is_on_floor() and actor.actions.is_available():
			landed = true
			break
	if not check(rose and landed,"Jump did not leave the floor and restore grounded control"): return false
	if courtyard:
		if not await action(actor,&"light"): return false
		await frames(3)
		if not check(actor.model.animation.assigned_animation == "combat/sword_regular_a","Packaged combo did not begin with A"): return false
		var stamina: float = actor.stamina
		var first_serial: int = actor.actions.serial
		var follow_up: RefCounted = actor.actions.request("light",true)
		if not check(not follow_up.resolved and actor.stamina == stamina,"Queued attack spent stamina before starting"): return false
		for index in 90:
			if follow_up.resolved: break
			await frames(1)
		if not check(follow_up.accepted and actor.combo == 1 and actor.actions.serial == first_serial+1,"Packaged early follow-up was not chained"): return false
		var attack_pose: RefCounted = actor.presentation.sword_attack
		if not check(attack_pose.current != null and attack_pose.current.clip == &"combat/sword_regular_b" and attack_pose.serial == actor.actions.serial,"Packaged follow-up did not select B's pose driver"): return false
		# process_frame resumes before model _process callbacks. Observe the first
		# completed presentation pass before checking its sampled animation.
		await get_tree().process_frame
		if not check(actor.model.animation.assigned_animation == "combat/sword_regular_b","Packaged combo did not blend into B"): return false
		for index in 180:
			if actor.actions.is_available(): break
			await frames(1)
		if not check(actor.actions.is_available(),"Melee action did not finish"): return false
		await frames(15)
		if not check(actor.actions.serial == first_serial+1 and actor.actions.pending_result == null,"Packaged combo replayed without a fresh press"): return false
		if not await action(actor,&"heavy"): return false
		await frames(3)
		if not check(actor.model.animation.assigned_animation == &"combat/sword_heavy","Packaged heavy did not use UAL1 Sword_Attack"): return false
		for index in 180:
			if actor.actions.is_available(): break
			await frames(1)
		if not check(actor.actions.is_available(),"Packaged heavy did not finish"): return false
		actor.selected_spell = 0
		if not await action(actor,&"cast"): return false
		if not check(actor.model.equipment.current_sockets[&"sword"] == &"left_hip","Packaged cast did not stow the sword"): return false
		for index in 90:
			if actor.actions.released: break
			await frames(1)
		await get_tree().process_frame
		if not check(actor.actions.released and actor.model.animation.assigned_animation == &"casting/spell_shoot","Packaged cast did not sample its native release pose"): return false
		for index in 90:
			if actor.actions.is_available(): break
			await frames(1)
		await frames(2)
		if not check(actor.actions.is_available() and actor.model.animation.assigned_animation == &"combat/sword_idle" and actor.model.equipment.current_sockets[&"sword"] == &"right_hand","Packaged cast did not restore sword idle and equipment"): return false
		if not check(not world.boss.dead and not world.finished,"Encounter unexpectedly ended"): return false
	return check(not actor.dead and actor.health == actor.max_health,"Player was unexpectedly hurt during safe smoke actions")

func check_ual_review(world: Node3D) -> bool:
	var model: Node3D = world.player.model
	if not check(model.rig.identifier == &"ual1_65_v1" and model.skeleton.get_bone_count() == 65,"UAL review lost its canonical skeleton"): return false
	if not check(model.equipment != null,"UAL equipment controller did not load"): return false
	if not check(model.appearance.equip(load("res://assets/models/ual/chest_fixture.res")),"Packaged chest fixture could not equip"): return false
	if not check(not model.appearance.body[&"torso"].visible,"Equipped chest did not hide its covered body region"): return false
	for layout in [&"all_stowed",&"sword_shield",&"bow"]:
		if not check(model.equipment.set_layout(layout),"Packaged equipment layout was rejected: "+String(layout)): return false
		if not check(model.equipment.current_sockets.size() == 3,"Packaged sword, shield or bow marker is missing"): return false
	model.equipment.set_socket_labels_visible(true)
	await frames(2)
	model.equipment.set_socket_labels_visible(false)
	model.equipment.set_layout(&"sword_shield")
	model.appearance.unequip(&"torso")
	return check(model.appearance.body[&"torso"].visible,"Unequip did not restore the packaged body")

func exercise_swimming(lab: Node3D) -> bool:
	lab.go_to_station(5)
	var actor: CharacterBody3D = lab.player
	var station: Node3D = lab.stations[5]
	var intent := Intent.new()
	actor.submit_intent(intent)
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,station.to_global(Vector3(10,-1.1,0))))
	await frames(20)
	if not check(actor.swimming.active and actor.model.animation.assigned_animation == "swimming/swim_idle","Packaged water entry / UAL idle failed"): return false
	intent.swim_vertical = -1
	await frames(30)
	if not check(actor.swimming.underwater and actor.resources.breath < 20,"Packaged underwater movement / breath failed"): return false
	intent.swim_vertical = 1
	await frames(80)
	if not check(not actor.swimming.underwater,"Packaged resurfacing failed"): return false
	intent.swim_vertical = 0
	actor.reset_for_lab(Transform3D(Basis.IDENTITY,station.to_global(Vector3(10,-1.1,-6))))
	intent.movement = Vector3.FORWARD
	intent.swim_direction = Vector3.FORWARD
	intent.surface_motion = Vector2(0,1)
	await frames(150)
	if not check(not actor.swimming.active and actor.is_on_floor(),"Packaged ledge exit failed"): return false
	lab.go_to_station(0)
	return true

func run() -> void:
	var arena := await wait_world(ARENA)
	if failed or not check_world(arena,true): return
	if not await exercise_player(arena,true): return
	var first_arena_id := arena.get_instance_id()
	get_parent().change_world(LAB)
	var lab := await wait_world(LAB)
	if failed or not check_world(lab,false): return
	if not await exercise_player(lab,false): return
	if not await exercise_swimming(lab): return
	get_parent().change_world(UAL_REVIEW)
	var review := await wait_world(UAL_REVIEW)
	if failed or not check_world(review,false): return
	if not await check_ual_review(review): return
	if not await exercise_player(review,false): return
	get_parent().change_world(ARENA)
	arena = await wait_world(ARENA)
	if failed or not check_world(arena,true): return
	if not check(arena.get_instance_id() != first_arena_id,"Returning to the courtyard reused the unloaded world"): return
	await frames(12)
	if not check_character(arena.player,"Reloaded player") or not check_character(arena.boss,"Reloaded Warden"): return
	print("RELEASE SMOKE: PASS")
	get_tree().quit(0)
