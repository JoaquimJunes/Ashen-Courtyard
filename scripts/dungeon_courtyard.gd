extends Node3D
## PSX Dungeon meshes are exported at atlas-layout offsets and 10 units/m.
## Recenter each mesh on its own base; the combat floor keeps simple colliders.
const PATH := "res://assets/third_party/psx_dungeon/"
const ATLAS = preload("res://assets/third_party/psx_dungeon/Textures/Dungeon_Map.png")
var mesh_cache: Dictionary = {}

func piece(asset: String, at: Vector3, scale_factor: float = 0.2, yaw: float = 0.0, atlas: Texture2D = ATLAS) -> Node3D:
 if not mesh_cache.has(asset):
  var source := load(PATH+"Models/"+asset+".fbx").instantiate() as Node3D
  var imported := source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
  mesh_cache[asset] = imported.mesh
  source.free()
 var root := Node3D.new()
 root.name = asset
 add_child(root)
 root.position = at
 root.rotation.y = yaw
 root.scale = Vector3.ONE*scale_factor
 var mesh := MeshInstance3D.new()
 mesh.mesh = mesh_cache[asset]
 root.add_child(mesh)
 var box := mesh.get_aabb()
 mesh.position = -Vector3(box.get_center().x,box.position.y,box.get_center().z)
 mesh.material_override = PSXStyle.material(atlas)
 return root

func collider(size: Vector3, at: Vector3) -> void:
 var body := StaticBody3D.new()
 add_child(body)
 body.position = at
 var shape := CollisionShape3D.new()
 var box := BoxShape3D.new()
 box.size = size
 shape.shape = box
 body.add_child(shape)

func _ready() -> void:
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color("111820")
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color("9aaab4")
 env.ambient_light_energy = 0.55
 env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
 world.environment = env
 add_child(world)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-52,-28,0)
 sun.light_color = Color("d7c7aa")
 sun.light_energy = 0.8
 sun.shadow_enabled = true
 add_child(sun)
 collider(Vector3(28,0.5,28),Vector3(0,-0.25,0))
 for x in range(-3,4):
  for z in range(-3,4): piece("Floor_Tiles",Vector3(x*4,0,z*4))
 for side in [-1,1]:
  collider(Vector3(28,4,1),Vector3(0,2,side*14))
  collider(Vector3(1,4,28),Vector3(side*14,2,0))
  for i in range(-3,4):
   var name := "Wall_01" if i%2 == 0 else "Windowed_Wall_01"
   piece(name,Vector3(i*4,0,side*14))
   piece(name,Vector3(side*14,0,i*4),0.2,PI/2)
  for i in range(-2,3):
   for point in [Vector3(i*6,0,side*13.7),Vector3(side*13.7,0,i*6)]:
    piece("Pillar",point)
    collider(Vector3(0.9,6,0.9),point+Vector3(0,3,0))
 # A barred arch frames the Warden, with the same sealed arena boundary.
 piece("Arch",Vector3(0,2.8,-13.25),0.3)
 piece("Arch_Fence",Vector3(0,2.8,-13.15),0.3)
 piece("Door_03",Vector3(0,0,-13.1),0.25,0,preload("res://assets/third_party/psx_dungeon/Textures/Doors_Map.png"))
 for x in [-10,10]:
  for z in [-10,10]:
   piece("Block",Vector3(x,0,z),0.07)
   piece("Candle_02",Vector3(x,0.7,z),0.24)
   collider(Vector3(0.9,1.1,0.9),Vector3(x,0.55,z))
   var flame := Shapes.orb(self,0.11,Vector3(x,1.5,z),Color("ffa544"))
   flame.scale = Vector3(0.8,1.6,0.8)
   var light := OmniLight3D.new()
   light.position = Vector3(x,1.8,z)
   light.light_color = Color("ff9b45")
   light.omni_range = 6.0
   light.light_energy = 2.5
   add_child(light)
 for i in range(12):
  var side := -1 if i%2 == 0 else 1
  piece("Debris",Vector3(side*12.2,0,-10+(i/2)*4),0.11,i*0.8)
 piece("Barrel",Vector3(-11.5,0,-11.5),0.15,0,preload("res://assets/third_party/psx_dungeon/Textures/CratesAndBarrels_Map.png"))
