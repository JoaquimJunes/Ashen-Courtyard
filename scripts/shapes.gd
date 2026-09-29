extends RefCounted
class_name Shapes

static func material(color: Color, glow: bool = false) -> StandardMaterial3D:
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = 0.9
 if glow:
  m.emission_enabled = true
  m.emission = color
 return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 n.mesh = mesh
 n.material_override = material(color)
 parent.add_child(n)
 n.position = pos
 return n

static func orb(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
 var n := MeshInstance3D.new()
 var mesh := SphereMesh.new()
 mesh.radius = radius
 mesh.height = radius * 2
 mesh.radial_segments = 8
 mesh.rings = 4
 n.mesh = mesh
 n.material_override = material(color, true)
 parent.add_child(n)
 n.position = pos
 return n

static func solid(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
 var body := StaticBody3D.new()
 parent.add_child(body)
 body.position = pos
 box(body, size, Vector3.ZERO, color)
 var collider := CollisionShape3D.new()
 var shape := BoxShape3D.new()
 shape.size = size
 collider.shape = shape
 body.add_child(collider)
 return body
