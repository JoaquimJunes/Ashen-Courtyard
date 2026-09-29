extends Node3D
@export var player_visual: PackedScene
var player: Combatant
var stations: Dictionary = {}
var active_station := 0
var hud: CanvasLayer
var recovery_pending := false
var reset_count := 0
var recovery_generation := 0
var test_hit_pending := false
var services: Node
var practice: Node3D
var review = preload("res://features/laboratory/movement_review.gd").new()

func _ready() -> void:
 services = GameSession.configure_world(self)
 GameInput.configure()
 for station: LabStation in $Stations.get_children():
  stations[station.station_id] = station
  station.recovery_requested.connect(request_recovery)
 build_access()
 build_lighting()
 player = GameSession.create_player(self,services,false,player_visual)
 review.configure(player)
 practice = preload("res://features/laboratory/movement_practice.tscn").instantiate()
 add_child(practice)
 practice.configure(player,services)
 player.died.connect(on_player_died)
 var retro := CanvasLayer.new()
 retro.name = "RetroEffects"
 retro.set_script(preload("res://scripts/retro_effects.gd"))
 add_child(retro)
 hud = CanvasLayer.new()
 hud.set_script(preload("res://scripts/lab_hud.gd"))
 hud.lab = self
 add_child(hud)
 go_to_station(0)
 Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func build_access() -> void:
 var color := Color("46585f")
 var paths := Node3D.new()
 paths.name = "Walkways"
 add_child(paths)
 for x in [-22,22]: Shapes.solid(paths,Vector3(4,0.4,108),Vector3(x,-0.2,0),color)
 for z in [-19,19]: Shapes.solid(paths,Vector3(128,0.4,6),Vector3(0,-0.2,z),color)
 for x in [-67,67]: Shapes.solid(paths,Vector3(6,0.4,120),Vector3(x,-0.2,0),color)
 for z in [-57,57]: Shapes.solid(paths,Vector3(128,0.4,6),Vector3(0,-0.2,z),color)
 for x in [-70,70]: Shapes.solid(paths,Vector3(0.3,1.2,120),Vector3(x,0.6,0),Color("a1b4b7"))
 for z in [-60,60]: Shapes.solid(paths,Vector3(140,1.2,0.3),Vector3(0,0.6,z),Color("a1b4b7"))
 # Navigation markings stay outside collision paths.
 for x in [-22,22]:
  for z in range(-50,51,5): Shapes.box(paths,Vector3(0.12,0.02,0.8),Vector3(x,0.015,z),Color("d9e3d8"))
 for z in [-19,19]:
  for x in range(-60,61,5): Shapes.box(paths,Vector3(0.8,0.02,0.12),Vector3(x,0.015,z),Color("d9e3d8"))

func build_lighting() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("c2d4de")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("d7e3ec")
 env.ambient_light_energy = 0.5
 world.environment = env
 add_child(world)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-50,-25,0)
 light.light_energy = 0.65
 light.shadow_enabled = true
 light.directional_shadow_max_distance = 90.0
 add_child(light)

func _physics_process(_delta: float) -> void:
 if not is_instance_valid(player): return
 if test_hit_pending and not player.is_on_floor() and player.velocity.y < -1.0 and not player.dead:
  test_hit_pending = false
  var damage := preload("res://features/combat/damage_request.gd").new(5,StringName("lab_fall_hit_%s" % recovery_generation))
  player.receive_damage(damage)
 for id: int in stations:
  if stations[id].contains(player.global_position):
   active_station = id
   break
 if practice.mode != 0 and not stations[0].contains(player.global_position):
  practice.mode = 0
  if player.state in [player.State.LIGHT,player.State.HEAVY,player.State.CAST,player.State.HEAL]:
   player.actions.cancel(&"left_practice")
  elif player.actions.buffered != "dodge":
   player.actions.reject_pending(&"left_practice")
  services.clear()
  practice.clear_target()
 var point := player.global_position
 var lower_limit := -7.0 if active_station == 5 else -4.0
 if point.y < lower_limit or point.y > 35 or absf(point.x) > 71 or absf(point.z) > 61:
  request_recovery(active_station)

func go_to_station(id: int) -> void:
 if not stations.has(id): return
 recovery_generation += 1
 test_hit_pending = false
 active_station = id
 services.clear()
 practice.reset_for_station(id)
 var spawn_at: Transform3D = practice.player_start.global_transform if practice.mode != 0 else stations[id].spawn.global_transform
 player.reset_for_lab(spawn_at)
 review.reset()
 if practice.mode != 0: player.target = practice.target

func set_practice_mode(mode: int) -> void:
 practice.mode = clampi(mode,0,2)
 go_to_station(0)

func start_fall_test(height: float, with_hit: bool = false) -> void:
 go_to_station(2)
 var rig: Node3D = stations[2].fixtures.get_node("FallTestRig")
 rig.configure_height(height)
 player.reset_for_lab(rig.start.global_transform)
 test_hit_pending = with_hit
 if with_hit: player.combat_enabled = true
 review.reset()

func start_ledge_test(index: int = 0) -> void:
 go_to_station(4)
 var rig: Node3D = stations[4].fixtures.get_node("LedgeTestRig")
 player.reset_for_lab(rig.starts[clampi(index,0,3)].global_transform)
 review.reset()

func start_ledge_corner_test(index: int = 0) -> void:
 go_to_station(4)
 var rig: Node3D = stations[4].fixtures.get_node("LedgeCornerRig")
 player.reset_for_lab(rig.starts[clampi(index,0,2)].global_transform)
 review.reset()

func reset_station() -> void:
 stations[active_station].reset_station()
 go_to_station(active_station)
 reset_count += 1

func reset_all() -> void:
 for station in stations.values(): station.reset_station()
 practice.mode = 0
 go_to_station(0)
 reset_count += 1

func request_recovery(id: int) -> void:
 if recovery_pending: return
 recovery_pending = true
 recover.call_deferred(id)

func on_player_died() -> void:
 var generation := recovery_generation
 if player.reactions.active:
  await get_tree().create_timer(2.5,false).timeout
 if generation == recovery_generation and is_instance_valid(player) and player.dead:
  request_recovery(active_station)

func recover(id: int) -> void:
 if stations.has(id): active_station = id
 reset_station()
 recovery_pending = false

func return_to_courtyard() -> void:
 GameSession.change_world("res://scenes/arena.tscn")
