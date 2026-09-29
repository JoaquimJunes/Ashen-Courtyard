extends Node3D
## Presentation only: shape and anchor displays follow existing gameplay results.
var actor: CharacterBody3D
var contacts: Node3D
var capsule: MeshInstance3D
var hitboxes: Node3D
var hitboxes_enabled := false:
	set(value):
		hitboxes_enabled = value
		sync_processing()
var hands_enabled := false:
	set(value):
		hands_enabled = value
		sync_processing()
var route_enabled := false:
	set(value):
		route_enabled = value
		sync_processing()
var capsule_enabled := false:
	set(value):
		capsule_enabled = value
		sync_processing()

func configure(character: CharacterBody3D) -> void:
	actor = character
	process_mode = Node.PROCESS_MODE_ALWAYS
	contacts = preload("res://features/laboratory/ledge_diagnostics.gd").new()
	add_child(contacts)
	contacts.configure(actor.traversal)
	capsule = MeshInstance3D.new()
	capsule.mesh = CapsuleMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5,0.9,0.8,0.18)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	capsule.material_override = material
	add_child(capsule)
	hitboxes = preload("res://features/ui/hitbox_debug.gd").new()
	add_child(hitboxes)
	hitboxes.configure(actor)
	visibility_changed.connect(sync_processing)
	hide()
	sync_processing()

func sync_processing() -> void:
	if contacts == null or capsule == null: return
	var active := is_visible_in_tree()
	contacts.show_hands = hands_enabled
	contacts.show_route = route_enabled
	contacts.visible = active and (hands_enabled or route_enabled)
	capsule.visible = active and capsule_enabled
	hitboxes.visible = active and hitboxes_enabled
	set_process(capsule.visible or hitboxes.visible)
	if is_processing(): _process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(actor): return
	capsule.mesh.height = actor.motor.capsule.height
	capsule.mesh.radius = actor.motor.capsule.radius
	capsule.global_transform = actor.motor.shape_node.global_transform
	if hitboxes.visible: hitboxes.refresh()
