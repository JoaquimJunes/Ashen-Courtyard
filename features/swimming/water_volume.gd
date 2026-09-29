extends Area3D
## Authored, stationary water box. Origin is the centre of its horizontal surface.
## Group lookup is world-filtered and also works on a character's first tick.
@export var size := Vector3(12,4,12)
@export var show_surface := true
const GROUP := &"swimming_water"

func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	collision.position.y = -size.y*0.5
	add_child(collision)
	if show_surface:
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x,size.z)
		mesh.mesh = plane
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.16,0.48,0.58,0.48)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.7
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)

func surface_y() -> float: return global_position.y

func contains(point: Vector3, margin: float = 0.0) -> bool:
	var local := to_local(point)
	return absf(local.x) <= size.x*0.5+margin and absf(local.z) <= size.z*0.5+margin and local.y <= margin and local.y >= -size.y-margin

func crossing(from: Vector3, to: Vector3) -> float:
	# Slab intersection catches vertical entry and fast movement through side walls.
	var a := to_local(from)
	var b := to_local(to)
	var low := Vector3(-size.x*0.5,-size.y,-size.z*0.5)
	var high := Vector3(size.x*0.5,0,size.z*0.5)
	var first := 0.0
	var last := 1.0
	for axis in 3:
		var travel: float = b[axis]-a[axis]
		if absf(travel) < 0.000001:
			if a[axis] < low[axis] or a[axis] > high[axis]: return -1.0
		else:
			var t1: float = (low[axis]-a[axis])/travel
			var t2: float = (high[axis]-a[axis])/travel
			first = maxf(first,minf(t1,t2))
			last = minf(last,maxf(t1,t2))
			if first > last: return -1.0
	return first

static func at(observer: Node3D, point: Vector3, margin: float = 0.0) -> Area3D:
	if not observer.is_inside_tree(): return null
	for water in observer.get_tree().get_nodes_in_group(GROUP):
		if water is Area3D and not water.is_queued_for_deletion() and water.get_world_3d() == observer.get_world_3d() and water.contains(point,margin): return water
	return null

static func crossed(observer: Node3D, from: Vector3, to: Vector3) -> Dictionary:
	var result := {}
	var earliest := INF
	for water in observer.get_tree().get_nodes_in_group(GROUP):
		if not water is Area3D or water.is_queued_for_deletion() or water.get_world_3d() != observer.get_world_3d(): continue
		var fraction: float = water.crossing(from,to)
		if fraction >= 0 and fraction < earliest:
			earliest = fraction
			result = {"water":water,"point":from.lerp(to,fraction)}
	return result
