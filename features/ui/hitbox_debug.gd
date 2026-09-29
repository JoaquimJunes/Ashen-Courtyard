extends Node3D
## Read-only display of the authoritative sensing snapshot; no physics queries.
var actor: CharacterBody3D
var regions: Array[MeshInstance3D] = []
var mouth: MeshInstance3D
var contact: MeshInstance3D
var label: Label3D

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.no_depth_test = true
	result.albedo_color = color
	return result

func dot(radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius*2
	mesh.mesh = sphere
	mesh.material_override = material(color)
	add_child(mesh)
	return mesh

func configure(character: CharacterBody3D) -> void:
	actor = character
	if actor.hitboxes == null: return
	for region in actor.hitboxes.regions:
		var mesh := MeshInstance3D.new()
		mesh.mesh = region.definition.shape.get_debug_mesh()
		mesh.material_override = material(Color("74caff"))
		add_child(mesh)
		regions.append(mesh)
	mouth = dot(0.025,Color("74ffc6"))
	contact = dot(0.035,Color("ffa45e"))
	label = Label3D.new()
	label.font_size = 24
	label.pixel_size = 0.002
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)

func refresh() -> void:
	if not is_instance_valid(actor) or actor.hitboxes == null or not actor.hitboxes.enabled: return
	for i in regions.size(): regions[i].global_transform = actor.hitboxes.world_transform(actor.hitboxes.regions[i])
	var head: RefCounted = actor.swimming.head_detector
	mouth.global_position = actor.hitboxes.breathing_position()
	label.global_position = mouth.global_position+Vector3.UP*0.22
	label.text = "HEAD UNDERWATER" if head.head_submerged else "HEAD IN AIR"
	contact.visible = not actor.hitboxes.last_contact.is_empty()
	if contact.visible: contact.global_position = actor.hitboxes.last_contact.position
