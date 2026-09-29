extends RefCounted
## Query snapshot with weak surface references; never persisted or shared as tuning.
var query_tick := 0
var from_water := false
var lip := Vector3.ZERO
var normal := Vector3.ZERO
var top_normal := Vector3.UP
var left_normal := Vector3.ZERO
var right_normal := Vector3.ZERO
var left_hand := Vector3.ZERO
var right_hand := Vector3.ZERO
var hang := Vector3.ZERO
var lift := Vector3.ZERO
var over := Vector3.ZERO
var stand := Vector3.ZERO
var can_mantle := false
var reason: StringName = &"unchecked"
var surfaces: Array[WeakRef] = []
var transforms: Array[Transform3D] = []
var local_lips: Array[Vector3] = []

func add_surface(surface: Node3D) -> void:
	for ref in surfaces:
		if ref.get_ref() == surface: return
	surfaces.append(weakref(surface))
	transforms.append(surface.global_transform)
	local_lips.append(surface.to_local(lip))

func valid() -> bool:
	for i in surfaces.size():
		var node = surfaces[i].get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree(): return false
		if not node.global_transform.is_equal_approx(transforms[i]): return false
	return not surfaces.is_empty()
