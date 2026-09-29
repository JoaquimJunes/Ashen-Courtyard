extends SceneTree
const Body = preload("res://features/character/body_definition.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",description)

func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var player: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	var second: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
	var boss: CharacterBody3D = load("res://scenes/boss.tscn").instantiate()
	for actor in [player,second,boss]:
		actor.controller.manual = true
		host.add_child(actor)
		actor.set_physics_process(false)
	await physics_frame
	await process_frame
	check(player.collision_layer == 2 and player.collision_mask == 7 and is_equal_approx(player.capsule.radius,0.32) and is_equal_approx(player.capsule.height,1.8),"Player preserves its collision layer, mask and capsule dimensions")
	check(boss.collision_layer == 4 and boss.collision_mask == 7 and is_equal_approx(boss.capsule.radius,0.45) and is_equal_approx(boss.capsule.height,2.5),"Warden preserves its collision layer, mask and capsule dimensions")
	check(player.model.scene_file_path == player.model_scene.resource_path and boss.model.scene_file_path == "res://scenes/models/psx_warden.tscn","Player uses its configured model and Warden retains its legacy model")
	check(player.sword == player.model.get_node("WeaponPivot") and boss.sword == boss.model.get_node("WeaponPivot"),"Model presentation exposes the same weapon pivots")
	check(player.model.locomotion.tuning == player.tuning.presentation and boss.model.locomotion.tuning == boss.tuning.presentation,"Both models receive their existing locomotion definitions")
	check(player.body_definition == second.body_definition and player.capsule != second.capsule,"Shared body definitions produce independent runtime shapes")
	player.capsule.height = 1.0
	check(is_equal_approx(second.capsule.height,1.8) and is_equal_approx(player.body_definition.height,1.8),"Runtime posture changes cannot mutate shared definitions or another character")
	player.capsule.height = 1.8
	player.take_damage(5,"visual_probe")
	player.visuals.tick(0.01,false)
	check(is_equal_approx(player.model.position.y,0.06) and second.visuals.flash == 0,"Accepted damage drives instance-local hit feedback")
	player.visuals.tick(0.2,false)
	check(player.model.position.y == 0,"Hit feedback ends at the original duration")
	player.reset_for_lab(Transform3D.IDENTITY)
	check(player.visuals.flash == 0 and player.model.position == Vector3.ZERO,"Player reset clears visual feedback")
	boss.take_damage(boss.health,"death_probe")
	boss.visuals.tick(0.1,true)
	check(boss.dead and boss.model.rotation.z > 0,"Warden retains its death pose feedback")
	# A small enemy needs neither knight visuals nor the large-body preset.
	var body := Body.new()
	body.radius = 0.2
	body.height = 0.8
	body.collision_layer = 4
	body.collision_mask = 1
	var plain := Combatant.new()
	host.add_child(plain)
	plain.setup(50,body)
	check(plain.get_child_count() == 1 and plain.get_child(0) is CollisionShape3D,"Generic Combatant assembles without a model, weapon or session services")
	check(plain.collision_layer == 4 and plain.collision_mask == 1 and is_equal_approx(plain.capsule.height,0.8),"Collision size and team layer are independently configurable")
	var health_events: Array[float] = []
	plain.health_changed.connect(func(current, _maximum): health_events.append(current))
	check(plain.take_damage(10,"plain_hit") and plain.health == 40 and health_events == [40.0],"Model-free damage forwards health exactly once")
	plain.tick_damage_history(8.1)
	check(plain.received.is_empty(),"Damage history expires without a visual tick")
	plain.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(10,10,0)))
	plain.motor.step(1.0/60,plain.tuning.gravity,false)
	check(plain.velocity.y < 0,"Model-free Combatant uses the shared motor")
	host.queue_free()
	await process_frame
	print("COMBATANT COMPOSITION: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
