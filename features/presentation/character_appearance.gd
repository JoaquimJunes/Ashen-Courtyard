extends RefCounted
## Visual-only equipment. Validate replacements before touching the live body.
const Definition = preload("res://features/presentation/appearance_definition.gd")
const Contacts = preload("res://features/presentation/skin_contact_cache.gd")
const SLOTS = [&"head",&"torso",&"hands",&"legs",&"feet"]
const REST_TOLERANCE = 0.0001
const WEIGHT_TOLERANCE = 0.0001
var skeleton: Skeleton3D
var rig_id: StringName
var body: Dictionary = {}
var equipment: Dictionary = {}
var contact: MeshInstance3D
var last_error := ""
static var validated_meshes: Dictionary = {}
var slots: Array[StringName] = []
signal body_changed

func configure(value: Skeleton3D, identifier: StringName, allowed_slots: Array[StringName] = []) -> void:
	skeleton = value
	rig_id = identifier
	slots.assign(SLOTS)
	if not allowed_slots.is_empty(): set_slots(allowed_slots)

func set_slots(value: Array[StringName]) -> bool:
	last_error = ""
	var seen := {}
	for slot in value:
		if slot == &"" or seen.has(slot):
			last_error = "Equipment slots must be unique nonempty names."
			return false
		seen[slot] = true
	for slot in equipment:
		if not seen.has(slot):
			last_error = "Cannot remove an occupied equipment slot."
			return false
	slots.assign(value)
	return true

func compatible(definition: Definition) -> bool:
	last_error = ""
	if definition == null or definition.rig_id != rig_id:
		last_error = "Appearance uses a different rig."
		return false
	if definition.regions.is_empty() or not definition.attachment_transform.is_finite():
		last_error = "Appearance needs geometry and a finite attachment transform."
		return false
	for region in definition.regions:
		if not (region is String or region is StringName) or str(region).is_empty():
			last_error = "Region names must be nonempty strings."
			return false
	var rigid := definition.attachment_bone != &""
	if rigid:
		# Rigid props follow one socket; they have no skin or full-armature contract.
		if skeleton.find_bone(definition.attachment_bone) < 0:
			last_error = "Unknown attachment bone."
			return false
		for region in definition.regions:
			var mesh = definition.regions[region]
			if not mesh is ArrayMesh:
				last_error = "Rigid region is not a mesh."
				return false
			if not valid_geometry(mesh): return false
			var transform: Variant = definition.region_transforms.get(region,Transform3D.IDENTITY)
			if not transform is Transform3D or not transform.is_finite():
				last_error = "Invalid rigid region transform."
				return false
		return true
	if definition.bone_names.size() != skeleton.get_bone_count() or definition.parent_names.size() != definition.bone_names.size() or definition.rest_transforms.size() != definition.bone_names.size():
		last_error = "Incomplete armature rest-pose manifest."
		return false
	var seen := {}
	for i in definition.bone_names.size():
		var bone := skeleton.find_bone(definition.bone_names[i])
		if bone < 0 or seen.has(bone):
			last_error = "Missing bone: "+definition.bone_names[i]
			return false
		seen[bone] = true
		var parent := skeleton.get_bone_parent(bone)
		var parent_name := skeleton.get_bone_name(parent) if parent >= 0 else ""
		if parent_name != definition.parent_names[i] or not near_transform(skeleton.get_bone_rest(bone),definition.rest_transforms[i]):
			last_error = "Incompatible rest pose: "+definition.bone_names[i]
			return false
	if definition.skin == null or definition.skin.get_bind_count() == 0:
		last_error = "Appearance needs skinned geometry."
		return false
	var bound := {}
	for bind in definition.skin.get_bind_count():
		var bone := skeleton.find_bone(definition.skin.get_bind_name(bind))
		if bone < 0 or bound.has(bone) or not near_transform(skeleton.get_bone_global_rest(bone).affine_inverse(),definition.skin.get_bind_pose(bind)):
			last_error = "Incompatible skin bind: "+str(bind)
			return false
		bound[bone] = true
	for mesh in definition.regions.values():
		if not mesh is ArrayMesh:
			last_error = "Region is not a skinned mesh."
			return false
		if not valid_mesh(mesh,definition.skin): return false
	if definition.contact_mesh != null and not valid_mesh(definition.contact_mesh,definition.skin): return false
	if definition.contact_mesh != null and not Contacts.valid_soles(definition.contact_mesh,definition.sole_vertices,definition.skin):
		last_error = "sole_vertices: need nonempty, unique, in-range IDs weighted to the matching foot/toes; regenerate the body asset."
		return false
	return true

func valid_geometry(mesh: ArrayMesh) -> bool:
	return valid_surface_data(mesh,-1)

func valid_mesh(mesh: ArrayMesh, skin: Skin) -> bool:
	if skin == null:
		last_error = "Missing skin or geometry."
		return false
	return valid_surface_data(mesh,skin.get_bind_count())

func valid_surface_data(mesh: ArrayMesh, bind_count: int) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		last_error = "Missing mesh geometry."
		return false
	# Compare the exact inputs, including surface count. Some engine mutations
	# (notably clear_surfaces) do not emit Resource.changed. Materials/UVs do not
	# affect geometry or skin validity, and rig/bind/sole checks stay per actor.
	var surfaces: Array = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		surfaces.append([arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX],arrays[Mesh.ARRAY_BONES],arrays[Mesh.ARRAY_WEIGHTS]])
	var id := mesh.get_instance_id()
	var cached: Dictionary = validated_meshes.get(id,{})
	if not cached.is_empty() and cached.source.get_ref() == mesh and cached.bind_count == bind_count and cached.surfaces == surfaces: return true
	for arrays in surfaces:
		var vertices: PackedVector3Array = arrays[0]
		if vertices.is_empty():
			last_error = "Empty mesh surface."
			return false
		for vertex in vertices:
			if not vertex.is_finite():
				last_error = "Nonfinite mesh vertex."
				return false
		if arrays[1] != null:
			for index in arrays[1]:
				if index < 0 or index >= vertices.size():
					last_error = "Mesh index is outside the vertex array."
					return false
		if bind_count < 0: continue
		if arrays[2] == null or arrays[3] == null:
			last_error = "Mesh lacks bone weights."
			return false
		var bones: PackedInt32Array = arrays[2]
		var weights: PackedFloat32Array = arrays[3]
		if bones.size() != vertices.size()*4 or weights.size() != bones.size():
			last_error = "Expected four skin influences per vertex."
			return false
		for vertex in vertices.size():
			var total := 0.0
			for influence in 4:
				var index := vertex*4+influence
				if bones[index] < 0 or bones[index] >= bind_count or not is_finite(weights[index]) or weights[index] < 0:
					last_error = "Invalid skin influence."
					return false
				total += weights[index]
			if absf(total-1.0) > WEIGHT_TOLERANCE:
				last_error = "Invalid vertex or unnormalized weights."
				return false
	if not validated_meshes.has(id):
		for old_id in validated_meshes.keys():
			if validated_meshes[old_id].source.get_ref() == null: validated_meshes.erase(old_id)
	validated_meshes[id] = {"source":weakref(mesh),"bind_count":bind_count,"surfaces":surfaces}
	return true

func near_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.is_finite() and b.is_finite() and a.origin.distance_to(b.origin) <= REST_TOLERANCE and a.basis.x.distance_to(b.basis.x) <= REST_TOLERANCE and a.basis.y.distance_to(b.basis.y) <= REST_TOLERANCE and a.basis.z.distance_to(b.basis.z) <= REST_TOLERANCE

func instance_mesh(mesh: ArrayMesh, skin: Skin, label: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.skin = skin
	skeleton.add_child(node)
	node.skeleton = node.get_path_to(skeleton)
	return node

func set_body(definition: Definition) -> bool:
	if not compatible(definition): return false
	if definition.slot != &"" or definition.contact_mesh == null or definition.attachment_bone != &"":
		last_error = "Body requires contact geometry and no equipment slot."
		return false
	for item in equipment.values():
		for region in item.definition.covered_regions:
			if not definition.regions.has(region):
				last_error = "Replacement body lacks covered region: "+str(region)
				return false
	for node in body.values(): node.free()
	body.clear()
	if is_instance_valid(contact): contact.free()
	contact = instance_mesh(definition.contact_mesh,definition.skin,"BodyContact")
	contact.set_meta("sole_vertices",definition.sole_vertices.duplicate(true))
	contact.hide()
	for region in definition.regions:
		body[region] = instance_mesh(definition.regions[region],definition.skin,"Body_"+str(region))
	refresh_coverage()
	body_changed.emit()
	return true

func equip(definition: Definition) -> bool:
	if not compatible(definition): return false
	if definition.slot not in slots:
		last_error = "Unknown equipment slot."
		return false
	for region in definition.covered_regions:
		if not body.has(region):
			last_error = "Equipment covers an unknown body region: "+str(region)
			return false
	var nodes: Array[Node3D] = []
	if definition.attachment_bone != &"":
		var socket := BoneAttachment3D.new()
		socket.bone_name = definition.attachment_bone
		skeleton.add_child(socket)
		nodes.append(socket)
		for region in definition.regions:
			var mesh := MeshInstance3D.new()
			mesh.mesh = definition.regions[region]
			socket.add_child(mesh)
			mesh.transform = definition.attachment_transform*definition.region_transforms.get(region,Transform3D.IDENTITY)
	else:
		for region in definition.regions: nodes.append(instance_mesh(definition.regions[region],definition.skin,"Armor_"+str(region)))
	unequip(definition.slot)
	equipment[definition.slot] = {"definition":definition,"nodes":nodes}
	refresh_coverage()
	return true

func unequip(slot: StringName) -> void:
	if equipment.has(slot):
		for node in equipment[slot].nodes: node.free()
		equipment.erase(slot)
	refresh_coverage()

func refresh_coverage() -> void:
	var hidden := {}
	for item in equipment.values():
		for region in item.definition.covered_regions: hidden[region] = true
	for region in body: body[region].visible = not hidden.has(region)
