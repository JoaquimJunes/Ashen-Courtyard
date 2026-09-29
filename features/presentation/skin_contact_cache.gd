extends RefCounted
## Exact CPU skin support queries. Geometry is shared; pose palettes belong to one actor.
const UAL_FOOT_NAMES = {"l":["foot_l","ball_l","ball_leaf_l"],"r":["foot_r","ball_r","ball_leaf_r"]}
class SupportGroup extends RefCounted:
	var bones := PackedInt32Array()
	var vertices := PackedInt32Array()
	var bounds := AABB()
	var radius := 0.0
	var minimum_weight := INF
	var maximum_weight := -INF

class Geometry extends RefCounted:
	var mesh: ArrayMesh
	var skin: Skin
	var vertices := PackedVector3Array()
	var joints := PackedInt32Array()
	var weights := PackedFloat32Array()
	var starts := PackedInt32Array([0])
	var source_vertices := PackedInt32Array()
	var bind_poses: Array[Transform3D] = []
	var bind_names := PackedStringArray()
	var support_groups: Array[SupportGroup] = []

	func build_support_groups() -> void:
		var groups := {}
		for vertex in vertices.size():
			var ids := joints.slice(starts[vertex],starts[vertex+1])
			ids.sort()
			if not groups.has(ids):
				var group := SupportGroup.new()
				group.bones = ids
				group.bounds = AABB(vertices[vertex],Vector3.ZERO)
				groups[ids] = group
				support_groups.append(group)
			var group: SupportGroup = groups[ids]
			group.vertices.append(vertex)
			group.bounds = group.bounds.expand(vertices[vertex])
			var total := 0.0
			for influence in range(starts[vertex],starts[vertex+1]): total += weights[influence]
			group.minimum_weight = minf(group.minimum_weight,total)
			group.maximum_weight = maxf(group.maximum_weight,total)
		for group in support_groups:
			group.radius = group.bounds.position.abs().max(group.bounds.end.abs()).length()

static var geometries: Dictionary = {}
var geometry: Geometry
var skeleton: Skeleton3D
var bone_ids := PackedInt32Array()
var palette: Array[Transform3D] = []
var builds := 0
var support_bounds := PackedFloat64Array()
var last_scanned_vertices := 0

func configure(node: MeshInstance3D, rig: Skeleton3D) -> void:
	if geometry != null and geometry.mesh == node.mesh and geometry.skin == node.skin and skeleton == rig: return
	skeleton = rig
	var key := str(node.mesh.get_instance_id())+":"+str(node.skin.get_instance_id())
	for old_key in geometries.keys():
		if geometries[old_key].get_ref() == null: geometries.erase(old_key)
	geometry = geometries[key].get_ref() if geometries.has(key) else null
	if geometry == null:
		geometry = Geometry.new()
		geometry.mesh = node.mesh
		geometry.skin = node.skin
		var seen := {}
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				var ids := PackedInt32Array()
				var values := PackedFloat32Array()
				for influence in 4:
					var index := vertex*4+influence
					if weights[index] > 0.0:
						ids.append(joints[index])
						values.append(weights[index])
				# Exact values only: UV/normal seams do not change skinned support.
				var signature := [vertices[vertex],ids,values]
				if not seen.has(signature):
					seen[signature] = geometry.vertices.size()
					geometry.vertices.append(vertices[vertex])
					geometry.joints.append_array(ids)
					geometry.weights.append_array(values)
					geometry.starts.append(geometry.joints.size())
				geometry.source_vertices.append(seen[signature])
		for bind in node.skin.get_bind_count():
			geometry.bind_poses.append(node.skin.get_bind_pose(bind))
			geometry.bind_names.append(node.skin.get_bind_name(bind))
		geometry.build_support_groups()
		geometries[key] = weakref(geometry)
	bone_ids.clear()
	palette.resize(geometry.bind_names.size())
	support_bounds.resize(geometry.support_groups.size())
	for name in geometry.bind_names: bone_ids.append(rig.find_bone(name))
	builds += 1

func update_palette(frame: Transform3D) -> void:
	skeleton.force_update_all_bone_transforms()
	for bind in bone_ids.size():
		palette[bind] = frame*skeleton.get_bone_global_pose(bone_ids[bind])*geometry.bind_poses[bind]

func point(vertex: int) -> Vector3:
	var result := Vector3.ZERO
	for influence in range(geometry.starts[vertex],geometry.starts[vertex+1]):
		result += palette[geometry.joints[influence]]*geometry.vertices[vertex]*geometry.weights[influence]
	return result

func minimum(model: Node3D, node: MeshInstance3D, rig: Skeleton3D, normal: Vector3) -> float:
	configure(node,rig)
	update_palette(model.global_transform.affine_inverse()*rig.global_transform)
	last_scanned_vertices = 0
	var first := -1
	var low := INF
	for index in geometry.support_groups.size():
		var bound := support_bound(geometry.support_groups[index],normal)
		if not is_finite(bound): bound = -INF # Numerical uncertainty must evaluate, never prune.
		support_bounds[index] = bound
		if bound < low:
			first = index
			low = bound
	if first < 0: return INF
	# Bounds only reject regions; they never become the returned body support.
	# Start with the most promising region to prune the rest against a real vertex.
	low = minimum_group(geometry.support_groups[first],normal,INF)
	for index in geometry.support_groups.size():
		if index != first and support_bounds[index] < low:
			low = minimum_group(geometry.support_groups[index],normal,low)
	return low

func support_bound(group: SupportGroup, normal: Vector3) -> float:
	if group.bones.is_empty(): return 0.0 # Original zero-influence result.
	var lower := INF
	var magnitude := 0.0
	for bone in group.bones:
		var transform := palette[bone]
		var direction := transform.basis.transposed()*normal
		var corner := group.bounds.position
		if direction.x < 0: corner.x += group.bounds.size.x
		if direction.y < 0: corner.y += group.bounds.size.y
		if direction.z < 0: corner.z += group.bounds.size.z
		lower = minf(lower,normal.dot(transform*corner))
		# Conservative magnitude also covers cancellation, non-unit normals and
		# scaled/sheared model frames when padding floating-point bound arithmetic.
		var size := transform.basis.x.length()+transform.basis.y.length()+transform.basis.z.length()
		magnitude = maxf(magnitude,normal.length()*(transform.origin.length()+size*group.radius))
	# Positive weights form a convex combination after dividing by their sum.
	# Preserve the actual sum: imported weights need not add to exactly one.
	lower *= group.maximum_weight if lower < 0 else group.minimum_weight
	return lower-0.00001*(1.0+magnitude*group.maximum_weight)

func minimum_group(group: SupportGroup, normal: Vector3, low: float) -> float:
	var vertices := geometry.vertices
	var starts := geometry.starts
	var joints := geometry.joints
	var weights := geometry.weights
	# Keep the hot loop flat: nested per-vertex Variant arrays are slower than skinning.
	for vertex in group.vertices:
		var value := Vector3.ZERO
		for influence in range(starts[vertex],starts[vertex+1]):
			value += palette[joints[influence]]*vertices[vertex]*weights[influence]
		low = minf(low,normal.dot(value))
	last_scanned_vertices += group.vertices.size()
	return low

## Read after update_palette(IDENTITY); both feet share one skeleton-space palette.
func sole_points(bone: int, indices: PackedInt32Array) -> Array[Vector3]:
	var inverse := skeleton.get_bone_global_pose(bone).affine_inverse()
	var result: Array[Vector3] = []
	for source in indices: result.append(inverse*point(geometry.source_vertices[source]))
	return result

## Source vertex IDs across contact surfaces. Aggregate toe/foot influences, including ties.
static func generate_soles(mesh: ArrayMesh, skin: Skin, names: Dictionary) -> Dictionary:
	var result := {"l":PackedInt32Array(),"r":PackedInt32Array()}
	var offset := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			for side in ["l","r"]:
				var weight := 0.0
				for influence in 4:
					var index := vertex*4+influence
					if skin.get_bind_name(joints[index]) in names[side]: weight += weights[index]
				# ArrayMesh may quantize 0.5 to 32767/65535. Match skin validation tolerance.
				if weight >= 0.5-0.0001: result[side].append(offset+vertex)
		offset += vertices.size()
	return result

static func valid_soles(mesh: ArrayMesh, data: Dictionary, skin: Skin, names: Dictionary = UAL_FOOT_NAMES) -> bool:
	if skin == null: return false
	var count := 0
	for surface in mesh.get_surface_count(): count += mesh.surface_get_array_len(surface)
	var selected := {}
	for side in ["l","r"]:
		if not data.get(side) is PackedInt32Array or data[side].is_empty() or not names.has(side): return false
		var seen := {}
		for index in data[side]:
			if index < 0 or index >= count or seen.has(index): return false
			seen[index] = true
		selected[side] = seen
	var offset := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var vertices := mesh.surface_get_array_len(surface)
		if joints.size() != vertices*4 or weights.size() != vertices*4: return false
		for vertex in vertices:
			for side in ["l","r"]:
				if not selected[side].has(offset+vertex): continue
				var total := 0.0
				for influence in 4:
					var index := vertex*4+influence
					if joints[index] < 0 or joints[index] >= skin.get_bind_count(): return false
					if not is_finite(weights[index]) or weights[index] < 0: return false
					if skin.get_bind_name(joints[index]) in names[side]: total += weights[index]
				if total < 0.5-0.0001: return false
		offset += vertices
	return true
