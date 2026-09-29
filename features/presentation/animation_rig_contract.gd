extends Resource
## Mesh-free reference contract; generated from the versioned authoring skeleton.
@export var rig_identifier: StringName = &"ual1_65_v1"
@export var bone_names: PackedStringArray
@export var parent_names: PackedStringArray
@export var rest_transforms: Array[Transform3D] = []
var last_error := ""
const TOLERANCE := 0.0001

func valid(skeleton: Skeleton3D = null) -> bool:
	last_error = ""
	if rig_identifier == &"" or bone_names.is_empty() or parent_names.size() != bone_names.size() or rest_transforms.size() != bone_names.size():
		return fail("Incomplete animation rig contract.")
	if skeleton != null and skeleton.get_bone_count() != bone_names.size(): return fail("Animation rig bone count differs from its reference.")
	var seen := {}
	for index in bone_names.size():
		var name := bone_names[index]
		var parent := parent_names[index]
		if name.is_empty() or seen.has(name) or (not parent.is_empty() and not seen.has(parent)) or not rest_transforms[index].is_finite(): return fail("Invalid animation rig hierarchy or rest transform: "+name)
		seen[name] = true
		if skeleton == null: continue
		var bone := skeleton.find_bone(name)
		if bone < 0: return fail("Animation rig is missing bone: "+name)
		var actual_parent := skeleton.get_bone_parent(bone)
		var actual_name := skeleton.get_bone_name(actual_parent) if actual_parent >= 0 else ""
		if actual_name != parent or not near_transform(skeleton.get_bone_rest(bone),rest_transforms[index]): return fail("Animation rig hierarchy/rest differs at bone: "+name)
	return true

func near_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.is_finite() and b.is_finite() and a.origin.distance_to(b.origin) <= TOLERANCE and a.basis.x.distance_to(b.basis.x) <= TOLERANCE and a.basis.y.distance_to(b.basis.y) <= TOLERANCE and a.basis.z.distance_to(b.basis.z) <= TOLERANCE

func fail(message: String) -> bool:
	last_error = message
	return false
