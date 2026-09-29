extends SceneTree
const Queries = preload("res://features/combat/damage_queries.gd")
const Strike = preload("res://features/combat/strike_token.gd")
const Geometry = preload("res://features/combat/hit_geometry.gd")
var checks := 0
var failures := 0
var world: Node3D
var player: CharacterBody3D
var attacker: Combatant

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ",message)

func settle() -> void:
	await physics_frame
	await process_frame

func pose(clip: String = "", time: float = 0.0) -> void:
	player.model.animation.stop()
	player.model.skeleton.reset_bone_poses()
	if clip != "":
		player.model.animation.play(clip)
		player.model.animation.seek(time,true)
		player.model.animation.advance(0)
	player.hitboxes.reset()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	player = preload("res://scenes/player.tscn").instantiate()
	player.controller.manual = true
	world.add_child(player)
	player.set_physics_process(false)
	player.model.set_process(false)
	attacker = Combatant.new()
	world.add_child(attacker)
	attacker.setup(100,preload("res://features/character/data/warden_body.tres"))
	attacker.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0,2)))
	var old_rate := Engine.physics_ticks_per_second
	for rate in [30,60,120]:
		Engine.physics_ticks_per_second = rate
		player.reset_for_lab(Transform3D.IDENTITY)
		player.model.set_process(false)
		pose()
		await settle()
		check(player.hitboxes.enabled and player.hitboxes.regions.size() == 17,"%s: full body profile active" % rate)
		for region in player.hitboxes.regions:
			var at: Transform3D = player.hitboxes.world_transform(region)
			var axis: Vector3 = at.basis.z.normalized()
			var hit := Queries.ray(attacker,at.origin-axis,at.origin+axis,3,attacker)
			check(not hit.is_empty() and hit.collider == player and hit.has("region"),"%s: actual ray hits %s" % [rate,region.definition.id])
			player.reset_resources()
			check(player.services.deal(attacker,player,10,Strike.new(),&"physical",hit) and player.health == 90,"%s: equal damage at %s" % [rate,region.definition.id])
		player.reset_resources()
		var gap := Queries.ray(attacker,Vector3(0,0.3,-1),Vector3(0,0.3,1),3,attacker)
		check(gap.is_empty(),"%s: clear gap between shins ignores broad capsule" % rate)
		check(Queries.ray(attacker,Vector3(0.24,1.65,-1),Vector3(0.24,1.65,1),3,attacker).is_empty(),"%s: near-head silhouette miss" % rate)
		check(Queries.ray(player,Vector3(0,1.65,-1),Vector3(0,1.65,1),3,player).is_empty(),"%s: own fitted regions cannot self-hit" % rate)
		for clip in ["k_idle","running/jog","crouch/crouch_idle","dodge/roll_forward","swimming/swim_forward","traversal/climb_up_1m_rm"]:
			pose(clip,0.25)
			var clock_before: float = player.model.animation.current_animation_position
			for region in player.hitboxes.regions:
				var bone: int = region.bone
				var expected: Transform3D = player.model.skeleton.global_transform*player.model.skeleton.get_bone_global_pose(bone)*region.definition.local_transform
				check(player.hitboxes.world_transform(region).is_equal_approx(expected),"%s: %s follows %s" % [rate,region.definition.id,clip])
				check(not player.hitboxes.ray(expected.origin-expected.basis.z,expected.origin+expected.basis.z).is_empty(),"%s: %s pose accepts body-region rays" % [rate,clip])
			check(player.model.animation.current_animation_position == clock_before,"%s: collision queries never advance %s" % [rate,clip])
		pose()
		var burst: Resource = player.tuning.burst.duplicate()
		burst.radius = 0.003 # Smaller than the measured 1.5 cm gap between these shins.
		burst.damage = 10
		var Aim = preload("res://features/combat/aim_request.gd")
		player.services.cast(attacker,burst,Aim.new(Vector3(0,0.3,0),Vector3.FORWARD),Strike.new())
		check(player.health == 100,"%s: small area in a limb gap misses the coarse capsule" % rate)
		var center: Vector3 = player.hitboxes.world_transform(player.hitboxes.regions[0]).origin
		var area_token := Strike.new()
		player.services.cast(attacker,burst,Aim.new(center,center+Vector3.FORWARD),area_token)
		player.services.cast(attacker,burst,Aim.new(center,center+Vector3.FORWARD),area_token)
		check(player.health == 90,"%s: area confirms fitted geometry and applies one strike" % rate)
		var head: Vector3 = player.hitboxes.breathing_position()
		var wall := Shapes.solid(world,Vector3(2,3,0.1),Vector3(0,1.5,0.7),Color.GRAY)
		await settle()
		var obstructed := Queries.ray(attacker,head+Vector3.BACK*2,head+Vector3.FORWARD*2,3,attacker)
		check(not obstructed.is_empty() and obstructed.collider == wall,"%s: wall precedes fitted hit" % rate)
		check(player.services.melee_contact(attacker,player,2.8).is_empty(),"%s: wall blocks melee to all regions" % rate)
		wall.free()
		await settle()
		var hit: Dictionary = player.services.melee_contact(attacker,player,2.8)
		var token := Strike.new()
		player.reset_resources()
		check(not hit.is_empty() and player.services.deal(attacker,player,10,token,&"physical",hit),"%s: melee volume confirms a fitted region" % rate)
		check(not player.services.deal(attacker,player,10,token,&"physical",hit) and player.health == 90,"%s: overlapping regions share one strike claim" % rate)
		check(not player.hitboxes.last_contact.is_empty(),"%s: accepted hit publishes debug contact" % rate)
		player.reset_resources()
		var projectile: Node3D = preload("res://scenes/projectile.tscn").instantiate()
		projectile.source = attacker
		projectile.hit_mask = 3
		projectile.speed = rate*8.0
		projectile.damage = 10
		world.add_child(projectile)
		projectile.set_physics_process(false)
		projectile.global_position = head+Vector3.BACK*4
		projectile.direction = Vector3.FORWARD
		projectile._physics_process(1.0/rate)
		check(player.health == 90 and projectile.is_queued_for_deletion(),"%s: fast projectile crosses and hits within one tick" % rate)
		await settle()
		player.reset_resources()
		player.reactions.begin(false,true)
		player.hitboxes.reset()
		var physical: Array[Transform3D] = player.reactions.driver.capture_physical_pose()
		var bone: int = player.model.skeleton.find_bone("Head")
		check(player.hitboxes.breathing_position().is_equal_approx(physical[bone]*player.hitboxes.profile.breathing_offset),"%s: ragdoll marker uses physical head" % rate)
		for region in player.hitboxes.regions:
			var at: Transform3D = player.hitboxes.world_transform(region)
			var ray := Queries.ray(attacker,at.origin-at.basis.z,at.origin+at.basis.z,3,attacker)
			check(not ray.is_empty() and ray.collider == player and ray.has("region"),"%s: ragdoll ray resolves fitted %s, not physical-bone damage" % [rate,region.definition.id])
		player.reactions.reset()
		player.hitboxes.reset()
	Engine.physics_ticks_per_second = old_rate
	var other: CharacterBody3D = preload("res://scenes/player.tscn").instantiate()
	other.model_scene = preload("res://scenes/models/psx_knight.tscn")
	other.position.x = 6
	world.add_child(other)
	other.set_physics_process(false)
	check(other.hitboxes.enabled and other.hitboxes.regions.size() == 17,"Legacy Knight has complete fitted profile")
	check(other.hitboxes != player.hitboxes and other.hitboxes.regions != player.hitboxes.regions,"Separate characters own separate sensing snapshots")
	var many: Array[Combatant] = []
	for i in 80:
		var body := Combatant.new()
		world.add_child(body)
		body.setup(100,preload("res://features/character/data/knight_body.tres"))
		body.position = Vector3(20+i,0,0)
		many.append(body)
	check(Queries.characters(attacker,2,attacker).size() == 82,"Candidate enumeration does not silently truncate at 64 shapes or actors")
	await settle()
	var fallback := Queries.ray(attacker,Vector3(99,1,2),Vector3(99,1,-2),3,attacker)
	check(not fallback.is_empty() and fallback.collider == many[-1],"Unprofiled receiver retains capsule ray path")
	var separate_world := SubViewport.new()
	separate_world.own_world_3d = true
	root.add_child(separate_world)
	var foreign := Combatant.new()
	separate_world.add_child(foreign)
	foreign.setup(100,preload("res://features/character/data/knight_body.tres"))
	check(Queries.characters(attacker,2,attacker).size() == 82,"Candidate registry excludes another physics world")
	check(Queries.contact(attacker,foreign,Vector3.ZERO,10).is_empty(),"An explicit target cannot bypass physics-world isolation")
	separate_world.queue_free()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	check(is_equal_approx(Geometry.segment(box,Vector3(-2,0,0),Vector3(2,0,0)),0.375),"Box segment returns actual earliest contact")
	var owned: RefCounted = player.hitboxes
	world.queue_free()
	await settle()
	check(not owned.enabled and owned.regions.is_empty(),"Unload removes fitted sensing state")
	print("FITTED HITBOXES: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
