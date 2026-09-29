class_name LabStation
extends Node3D
## Each scene is a self-contained 40 x 32 m module. Fixtures are static in milestone 1.
@export_enum("Hub", "Running", "Jumping", "Crouching", "Climbing", "Swimming", "Pushing", "Throwing", "Powered flight") var station_id := 0
@export var entrance := Vector3(0,0.05,14)
@export var entrance_yaw := 0.0
const TITLES := ["HUB / SPAWN", "RUNNING", "JUMPING", "CROUCHING", "CLIMBING", "SWIMMING", "PUSHING", "THROWING", "POWERED FLIGHT"]
const FLOOR := Color("6c787f")
const BLOCK := Color("9ba6aa")
const ACCENT := Color("efc274")
const INK := Color("273943")
var spawn: Marker3D
var fixtures: Node3D
var reset_objects: Array[Node3D] = []
var initial_transforms: Array[Transform3D] = []
signal recovery_requested(station_id: int)

func _ready() -> void:
 name = "Station%02d" % station_id
 fixtures = Node3D.new()
 fixtures.name = "Fixtures"
 add_child(fixtures)
 spawn = Marker3D.new()
 spawn.name = "EntranceSpawn"
 spawn.position = entrance
 spawn.rotation.y = entrance_yaw
 add_child(spawn)
 if station_id != 5: solid(Vector3(40,0.4,32),Vector3(0,-0.2,0),FLOOR)
 # Perimeter paint rather than walls: every station is accessible from the aisles.
 for x in [-19.8,19.8]: paint(Vector3(0.08,0.015,31.6),Vector3(x,0.009,0),ACCENT)
 for z in [-15.8,15.8]: paint(Vector3(39.6,0.015,0.08),Vector3(0,0.009,z),ACCENT)
 entrance_sign()
 match station_id:
  0: hub()
  1: running()
  2: jumping()
  3: crouching()
  4: climbing()
  5: swimming()
  6: pushing()
  7: throwing()
  8: flight()

func solid(size: Vector3, at: Vector3, color: Color = BLOCK) -> StaticBody3D:
 return Shapes.solid(fixtures,size,at,color)

func paint(size: Vector3, at: Vector3, color: Color = Color.WHITE) -> MeshInstance3D:
 return Shapes.box(fixtures,size,at,color)

func text_at(words: String, at: Vector3, size: float = 0.018, billboard: bool = true) -> Label3D:
 var label := Label3D.new()
 label.text = words
 label.font_size = 48
 label.pixel_size = size
 label.modulate = Color("f8f4dd")
 label.outline_modulate = INK
 label.outline_size = 8
 label.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
 label.visibility_range_end = 45.0
 if billboard: label.visibility_range_begin = 3.0
 fixtures.add_child(label)
 label.position = at
 return label

func floor_text(words: String, at: Vector3, size: float = 0.014) -> void:
 var label := text_at(words,at,size,false)
 label.rotation.x = -PI/2

func entrance_sign() -> void:
 var heading := "%02d  %s" % [station_id,TITLES[station_id]]
 var status := "EXISTING MOVEMENT / BASELINE" if station_id == 1 else "NOT ACTIVE YET"
 if station_id == 0: status = "ESC  DIRECTORY / RESET / CAMERA"
 if station_id == 2: status = "JUMP / FALL / LANDING REVIEW"
 if station_id == 3: status = "CROUCH ACTIVE / CRAWL NOT ACTIVE"
 if station_id == 4: status = "LEDGES ACTIVE / FREE CLIMB NOT ACTIVE"
 if station_id == 5: status = "SWIM / DIVE / LEDGE EXITS ACTIVE"
 var frame := Node3D.new()
 fixtures.add_child(frame)
 frame.position = entrance+Basis(Vector3.UP,entrance_yaw)*Vector3(5.5,1.7,-2)
 frame.rotation.y = entrance_yaw
 if station_id == 0:
  frame.position = Vector3(10,1.7,-9)
  frame.rotation.y = 0
 Shapes.solid(frame,Vector3(7,2.1,0.2),Vector3.ZERO,INK)
 var label := Label3D.new()
 label.text = heading+"\n"+status
 label.font_size = 42
 label.pixel_size = 0.0065
 label.modulate = ACCENT
 label.outline_size = 0
 label.position.z = 0.12
 frame.add_child(label)
 paint(Vector3(2,0.02,2),entrance-Vector3(0,0.035,0),Color("b1d6c9"))

func recovery_volume(size: Vector3, at: Vector3) -> void:
 var area := Area3D.new()
 area.name = "RecoveryVolume"
 area.collision_layer = 0
 area.collision_mask = 2
 fixtures.add_child(area)
 area.position = at
 var collision := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = size
 collision.shape = box
 area.add_child(collision)
 area.body_entered.connect(func(body):
  if body is Combatant: recovery_requested.emit(station_id)
 )

func ramp(at: Vector3, width: float, length: float, degrees: float) -> StaticBody3D:
 # Wedge rises toward -Z; at.y is the low endpoint's height.
 var h := tan(deg_to_rad(degrees))*length
 var vertices := [Vector3(-width/2,0,length/2),Vector3(width/2,0,length/2),
  Vector3(-width/2,0,-length/2),Vector3(width/2,0,-length/2),
  Vector3(-width/2,h,-length/2),Vector3(width/2,h,-length/2)]
 var surface := SurfaceTool.new()
 surface.begin(Mesh.PRIMITIVE_TRIANGLES)
 surface.set_smooth_group(-1)
 # Godot uses clockwise front faces for mesh and triangle collision.
 for i in [0,4,1,1,4,5,0,2,4,1,5,3,2,3,5,2,5,4,0,1,3,0,3,2]: surface.add_vertex(vertices[i])
 surface.generate_normals()
 var mesh := surface.commit()
 var body := StaticBody3D.new()
 fixtures.add_child(body)
 body.position = at
 var instance := MeshInstance3D.new()
 instance.mesh = mesh
 var mat := Shapes.material(BLOCK)
 mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 instance.material_override = mat
 body.add_child(instance)
 var collider := CollisionShape3D.new()
 collider.shape = mesh.create_trimesh_shape()
 body.add_child(collider)
 body.set_meta("slope_degrees",degrees)
 return body

func hub() -> void:
 for i in range(-10,11,2):
  paint(Vector3(20,0.012,0.035),Vector3(0,0.008,i),Color("b4c4c8"))
  paint(Vector3(0.035,0.012,20),Vector3(i,0.008,0),Color("b4c4c8"))
 floor_text("CHARACTER TEST GROUNDS",Vector3(0,0.03,-3),0.028)
 floor_text("140 x 120 m / ENVIRONMENT MILESTONE",Vector3(0,0.03,0))
 floor_text("NORTH: CLIMB / FLIGHT / SWIM",Vector3(0,0.03,-13),0.010)
 floor_text("SOUTH: RUN / CROUCH / PUSH",Vector3(0,0.03,13),0.010)
 floor_text("02 JUMP",Vector3(-16,0.03,0),0.012)
 floor_text("07 THROW",Vector3(16,0.03,0),0.012)
 solid(Vector3(2,1,1),Vector3(-7,0.5,5),INK)
 text_at("DIRECTORY + RESET\nUse the Esc menu",Vector3(-7,2,5),0.008)

func running() -> void:
 paint(Vector3(30,0.018,3),Vector3(0,0.012,-8),Color("506c79"))
 for meter in 31:
  var x := float(meter)-15
  paint(Vector3(0.04,0.02,3),Vector3(x,0.025,-8))
  if meter%5 == 0: floor_text(str(meter)+" m",Vector3(x,0.035,-10.5),0.012)
 for i in 3:
  var angle: float = [10.0,20.0,30.0][i]
  ramp(Vector3(-13+i*6,0,3),3,8,angle)
  text_at(str(int(angle))+"°",Vector3(-13+i*6,0.8,8),0.014)
 for i in 25:
  var z := -3.0+i*0.5
  paint(Vector3(0.18,0.02,0.18),Vector3(9+sin(i*0.3)*3,0.02,z),ACCENT)
 solid(Vector3(0.4,2,5),Vector3(15,1,4))
 solid(Vector3(5,2,0.4),Vector3(12.7,1,6.3))
 text_at("S-TURNS + CORNERS",Vector3(10,2,10),0.012)
 for i in 3:
  var height: float = [0.25,0.6,0.7][i]
  var x := -14.0+i*6
  solid(Vector3(3,height,2),Vector3(x,height/2,12))
  floor_text("%.2f m%s" % [height," / BLOCKED" if i == 2 else " / STEP"],Vector3(x,0.03,14),0.007)

func jumping() -> void:
 var drop_rig := preload("res://features/laboratory/fall_test_rig.tscn").instantiate()
 drop_rig.name = "FallTestRig"
 drop_rig.position = Vector3(2,0,-1)
 fixtures.add_child(drop_rig)
 var gaps := [0.5,1.0,2.0,3.0]
 for i in 4:
  var z := -10.5+i*7
  var gap: float = gaps[i]
  var height := 0.5+i*0.25
  solid(Vector3(3,height,3),Vector3(-15,height/2,z))
  # Existing walking step-up provides access without adding a jump mechanic.
  for step in 3:
   var rise := height*float(step+1)/3.0
   solid(Vector3(0.8,rise,2),Vector3(-18.5+step*0.8,rise/2,z))
  solid(Vector3(3,height,3),Vector3(-12+gap,height/2,z))
  paint(Vector3(gap,0.02,3),Vector3(-13.5+gap/2,0.018,z),Color("ce9972"))
  recovery_volume(Vector3(gap,0.12,3),Vector3(-13.5+gap/2,0.08,z))
  text_at("%.1f m GAP" % gap,Vector3(-12,2.6,z),0.012)
 for i in 5:
  var height: float = [0.25,0.5,1.0,1.5,2.0][i]
  solid(Vector3(3,height,3),Vector3(0+i*3.7,height/2,-8))
  text_at("%.2f m" % height,Vector3(i*3.7,height+0.5,-8),0.009)
 solid(Vector3(8,0.3,3),Vector3(5,2.7,6))
 solid(Vector3(0.4,2.7,3),Vector3(1,1.35,6))
 solid(Vector3(0.4,2.7,3),Vector3(9,1.35,6))
 floor_text("CATCH FLOOR / AUTO RESET",Vector3(-8,0.03,14),0.012)
 # Exact raised-gap examples; the 0.6 m start deck is reachable by walking.
 for i in 2:
  var rig := preload("res://features/laboratory/dive_clearance_rig.tscn").instantiate()
  rig.name = "AdaptiveDiveGap%d" % i
  rig.gap = 0.5+i*0.1
  rig.width = 2.5
  rig.position = Vector3(12+i*4,0,7)
  fixtures.add_child(rig)
  recovery_volume(Vector3(2.5,0.12,rig.gap),Vector3(rig.position.x,0.08,7-rig.gap/2))
 floor_text("DIVE: 0.60 m TO 1.00 m",Vector3(14,0.03,12),0.010)

func crouching() -> void:
 floor_text("CROUCH: 1 m / HOLD CROUCH 0.5 s: CRAWL 0.9 m",Vector3(0,0.03,7),0.009)
 for i in 3:
  var x := -12.0+i*12
  var height: float = [1.0,1.2,1.5][i]
  solid(Vector3(3.6,0.35,10),Vector3(x,height+0.175,-1))
  for side in [-1,1]: solid(Vector3(0.3,height,10),Vector3(x+side*1.65,height/2,-1))
  text_at("%.1f m CLEARANCE" % height,Vector3(x,2.4,-7.5),0.012)
 for x in [-6.0,6.0]:
  var height := 0.9 if x < 0 else 0.8
  var roof := solid(Vector3(3,0.25,10),Vector3(x,height+0.125,-1),Color("8b919b"))
  roof.name = "CrawlTunnel" if x < 0 else "CrawlBlockedTunnel"
  for side in [-1,1]: solid(Vector3(0.2,height,10),Vector3(x+side*1.4,height*0.5,-1))
  text_at("CRAWL %.2f m" % height,Vector3(x,1.5,-7.5),0.010)
 solid(Vector3(2.6,0.02,1.2),Vector3(-6,0.01,-1))
 solid(Vector3(2.6,0.02,1.2),Vector3(-6,0.89,-3.5))
 solid(Vector3(8,0.4,5),Vector3(10,1.2,10))
 floor_text("BLOCKED STAND TEST",Vector3(0,0.03,10),0.012)

func climbing() -> void:
 var corners := preload("res://features/laboratory/ledge_corner_rig.tscn").instantiate()
 corners.position = Vector3(-12,0,2)
 fixtures.add_child(corners)
 var rig := preload("res://features/laboratory/ledge_test_rig.tscn").instantiate()
 rig.position = Vector3(-14,0,10)
 fixtures.add_child(rig)
 for i in 3:
  var x := -13.0+i*9
  var height := 4.0+i*4
  solid(Vector3(5,height,1),Vector3(x,height/2,-6))
  solid(Vector3(5,0.4,3),Vector3(x,height-0.2,-7))
  text_at("%d m WALL" % int(height),Vector3(x,1.8,-3.8),0.012)
  for mark in int(height): paint(Vector3(0.5,0.035,0.025),Vector3(x-2,mark+0.5,-5.48),ACCENT)
 solid(Vector3(1,5,8),Vector3(14,2.5,2))
 solid(Vector3(7,5,1),Vector3(11,2.5,-1.5))
 solid(Vector3(5,0.5,4),Vector3(5,10.5,-3.5))
 floor_text("CORNERS",Vector3(12,0.03,8),0.012)
 floor_text("CATCH FLOOR",Vector3(-8,0.03,5),0.017)

func swimming() -> void:
 for z in [-12,12]: solid(Vector3(40,0.4,8),Vector3(0,-0.2,z),FLOOR)
 for x in [-16,16]: solid(Vector3(8,0.4,16),Vector3(x,-0.2,0),FLOOR)
 var depths := [0.4,1.2,4.5]
 for i in 3:
  var depth: float = depths[i]
  solid(Vector3(8,0.25,16),Vector3(-8+i*8,-depth-0.125,0),Color("628b9b"))
  text_at("%.1f m DEPTH" % depth,Vector3(-8+i*8,0.8,1),0.014)
 for z in [-8,8]: solid(Vector3(24,4.7,0.15),Vector3(0,-2.35,z))
 for x in [-12,12]: solid(Vector3(0.15,4.7,16),Vector3(x,-2.35,0))
 var water := preload("res://features/swimming/water_volume.tscn").instantiate()
 water.name = "SwimmingPool"
 water.size = Vector3(24,5,16)
 fixtures.add_child(water)
 ramp(Vector3(-8,-0.4,-6.5),3,3,rad_to_deg(atan(0.4/3.0)))
 for i in 8:
  var depth := (i+1)*0.5
  solid(Vector3(3,0.25,0.8),Vector3(8,-depth-0.125,-7.6+i*0.8))
 solid(Vector3(3,0.4,3),Vector3(7,0.2,9.4),Color("8b9d90"))
 text_at("0.4 m PULL-UP",Vector3(7,1.5,10),0.012)
 solid(Vector3(2.5,0.25,2.8),Vector3(2,1.45,8),Color("a18675"))
 text_at("BLOCKED EXIT",Vector3(2,2.1,8),0.012)
 solid(Vector3(3,0.35,2),Vector3(8,-1.65,-1),Color("607e86"))
 solid(Vector3(0.5,2.5,2),Vector3(6.75,-3,-1),Color("607e86"))
 solid(Vector3(0.5,2.5,2),Vector3(9.25,-3,-1),Color("607e86"))
 floor_text("SHALLOW ENTRY  /  DEEP DIVE  /  SWIM TO LEDGE TO EXIT",Vector3(0,0.03,11),0.009)

func register_object(object: Node3D) -> void:
 reset_objects.append(object)
 initial_transforms.append(object.transform)

func pushing() -> void:
 for i in 3:
  var x := -12.0+i*12
  paint(Vector3(3,0.02,20),Vector3(x,0.014,0),Color("63777b"))
  var crate := solid(Vector3(1.3,1.3,1.3),Vector3(x,0.65,-6),Color("af9c7a"))
  crate.name = ["LightCrate","MediumCrate","HeavyCrate"][i]
  register_object(crate)
  text_at(["LIGHT","MEDIUM","HEAVY"][i]+" / STATIC",Vector3(x,2.2,-6),0.012)
  for z in [-3,0,3,6]: paint(Vector3(3,0.02,0.06),Vector3(x,0.028,z),ACCENT)
 ramp(Vector3(0,0,6),3,6,10).rotation.y = PI
 solid(Vector3(0.4,1.5,5),Vector3(14,0.75,5))
 solid(Vector3(4,1.5,0.4),Vector3(12.2,0.75,7.3))

func ring(at: Vector3, radius: float, normal_x: bool = false) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 var mesh := TorusMesh.new()
 mesh.inner_radius = radius-0.08
 mesh.outer_radius = radius+0.08
 mesh.rings = 20
 mesh.ring_segments = 6
 node.mesh = mesh
 node.material_override = Shapes.material(ACCENT)
 fixtures.add_child(node)
 node.position = at
 node.rotation = Vector3(0,0,PI/2) if normal_x else Vector3(PI/2,0,0)
 return node

func throwing() -> void:
 for i in 5:
  var distance := (i+1)*5
  var x := -15.0+distance
  var z: float = [-5,-2,2,5,0][i]
  ring(Vector3(x,1.6,z),0.8,true)
  solid(Vector3(0.15,1.1,0.15),Vector3(x,0.55,z),INK)
  text_at(str(distance)+" m",Vector3(x,2.8,z),0.012)
  paint(Vector3(0.04,0.02,20),Vector3(x,0.018,0))
 for z in [-12,12]: solid(Vector3(32,2,0.3),Vector3(0,1,z))
 solid(Vector3(0.4,5,24),Vector3(16,2.5,0))
 solid(Vector3(2,1,4),Vector3(-16,0.5,8),INK)
 for i in 3:
  var ball := Shapes.orb(fixtures,0.23,Vector3(-16,1.24,7+i),Color("c3cbc8"))
  ball.material_override.emission_enabled = false
  register_object(ball)
 var rock := solid(Vector3(0.45,0.35,0.5),Vector3(-15.4,1.175,8),Color("8e979b"))
 register_object(rock)
 text_at("OBJECT RACK\nNOT ACTIVE YET",Vector3(-16,2.4,8),0.010)

func flight() -> void:
 var takeoff := ring(Vector3(0,0.06,7),3)
 takeoff.rotation = Vector3.ZERO
 floor_text("TAKEOFF / NOT ACTIVE YET",Vector3(0,0.03,11),0.012)
 for data in [Vector3(-12,4,-4),Vector3(10,10,-6),Vector3(-4,20,-10)]:
  solid(Vector3(5,0.5,5),data-Vector3(0,0.25,0))
  text_at("LANDING %d m" % int(data.y),data+Vector3.UP,0.012)
 for data in [Vector3(-10,4,6),Vector3(-7,8,-4),Vector3(8,12,-4),Vector3(0,20,-10)]: ring(data,1.8)
 solid(Vector3(0.3,30,0.3),Vector3(17,15,-12),INK)
 for height in [4,8,12,20,30]:
  paint(Vector3(1.5,0.06,0.3),Vector3(17,height,-11.8),ACCENT)
  text_at(str(height)+" m",Vector3(15.5,height,-11.5),0.014)

func reset_station() -> void:
 for i in reset_objects.size():
  if is_instance_valid(reset_objects[i]): reset_objects[i].transform = initial_transforms[i]

func contains(point: Vector3) -> bool:
 var local := to_local(point)
 return absf(local.x) <= 20 and absf(local.z) <= 16
