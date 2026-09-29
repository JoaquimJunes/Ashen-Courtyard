extends SceneTree
## Partition existing triangles, preserving seam positions, UVs and skin weights.
const Definition = preload("res://features/presentation/appearance_definition.gd")
const OUTPUT = "res://assets/models/ual/"
func _initialize() -> void: run.call_deferred()

func region_for(name: String) -> StringName:
	var side := "_l" if name.ends_with("_l") else "_r"
	if name.begins_with("thigh"): return StringName("thigh"+side)
	if name.begins_with("calf"): return StringName("calf"+side)
	if name.begins_with("foot") or name.begins_with("ball"): return StringName("foot"+side)
	if name.begins_with("upperarm"): return StringName("upperarm"+side)
	if name.begins_with("lowerarm"): return StringName("forearm"+side)
	if name.begins_with("hand") or name.begins_with("index") or name.begins_with("middle") or name.begins_with("ring") or name.begins_with("pinky") or name.begins_with("thumb"): return StringName("hand"+side)
	if name in ["Head","neck_01"]: return &"head"
	if name in ["root","pelvis"]: return &"pelvis"
	return &"torso"

func run() -> void:
	var source = load("res://assets/third_party/quaternius/UAL1_Standard.glb").instantiate()
	root.add_child(source)
	var skeleton: Skeleton3D = source.find_child("Skeleton3D",true,false)
	var mesh: MeshInstance3D = skeleton.find_children("*","MeshInstance3D",true,false)[0]
	var body := Definition.new()
	body.skin = mesh.skin.duplicate()
	body.contact_mesh = mesh.mesh
	body.sole_vertices = preload("res://features/presentation/skin_contact_cache.gd").generate_soles(body.contact_mesh,body.skin,{"l":["foot_l","ball_l","ball_leaf_l"],"r":["foot_r","ball_r","ball_leaf_r"]})
	for i in skeleton.get_bone_count():
		body.bone_names.append(skeleton.get_bone_name(i))
		var parent := skeleton.get_bone_parent(i)
		body.parent_names.append(skeleton.get_bone_name(parent) if parent >= 0 else "")
		body.rest_transforms.append(skeleton.get_bone_rest(i))
	var chest := Definition.new()
	chest.skin = body.skin
	chest.bone_names = body.bone_names
	chest.parent_names = body.parent_names
	chest.rest_transforms = body.rest_transforms
	chest.slot = &"torso"
	chest.covered_regions.assign([&"torso"])
	var chest_mesh := ArrayMesh.new()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var builders := {}
		var armor := SurfaceTool.new()
		armor.begin(Mesh.PRIMITIVE_TRIANGLES)
		var armor_vertices := 0
		if indices.is_empty():
			for i in positions.size(): indices.append(i)
		for triangle in range(0,indices.size(),3):
			var scores := {}
			for corner in 3:
				var v := indices[triangle+corner]
				for j in 4:
					var region := region_for(mesh.skin.get_bind_name(joints[v*4+j]))
					scores[region] = scores.get(region,0.0)+weights[v*4+j]
			var region: StringName = &"torso"
			var highest := -1.0
			for candidate in scores:
				if scores[candidate] > highest:
					highest = scores[candidate]
					region = candidate
			if not builders.has(region):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[region] = builder
			for corner in 3:
				var v := indices[triangle+corner]
				var builder: SurfaceTool = builders[region]
				builder.set_normal(normals[v])
				builder.set_uv(uvs[v])
				builder.set_bones(joints.slice(v*4,v*4+4))
				builder.set_weights(weights.slice(v*4,v*4+4))
				builder.add_vertex(positions[v])
				if region == &"torso":
					armor.set_normal(normals[v])
					armor.set_uv(uvs[v])
					armor.set_bones(joints.slice(v*4,v*4+4))
					armor.set_weights(weights.slice(v*4,v*4+4))
					armor.add_vertex(positions[v]+normals[v]*0.025)
					armor_vertices += 1
		for region in builders:
			if not body.regions.has(region): body.regions[region] = ArrayMesh.new()
			var builder: SurfaceTool = builders[region]
			builder.set_material(mesh.mesh.surface_get_material(surface))
			builder.index()
			builder.commit(body.regions[region])
		if armor_vertices > 0:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("46515c")
			material.metallic = 0.65
			material.roughness = 0.8
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			armor.set_material(material)
			armor.index()
			armor.commit(chest_mesh)
	chest.regions[&"chest"] = chest_mesh
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var body_error := ResourceSaver.save(body,OUTPUT+"mannequin_body.res")
	var chest_error := ResourceSaver.save(chest,OUTPUT+"chest_fixture.res")
	print("UAL appearance regions: ",body.regions.keys())
	source.free()
	quit(0 if body_error == OK and chest_error == OK else 1)
