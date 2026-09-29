extends RefCounted
class_name PSXStyle
const SURFACE = preload("res://shaders/psx_surface.gdshader")
class ChangeEvents extends RefCounted:
	signal enabled_changed(previous: bool, current: bool)
static var changes := ChangeEvents.new()
static var enabled := true:
	set(value):
		if enabled == value: return
		var previous := enabled
		enabled = value
		changes.enabled_changed.emit(previous,value)
static var material_cache: Dictionary = {}

static func material(texture: Texture2D, tint: Color = Color.WHITE) -> ShaderMaterial:
	var key := str(texture.get_instance_id() if texture else 0)+str(tint)
	if material_cache.has(key): return material_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE
	mat.set_shader_parameter("textured",texture != null)
	if texture: mat.set_shader_parameter("albedo_texture",texture)
	mat.set_shader_parameter("tint",tint)
	material_cache[key] = mat
	return mat

static func apply(node: Node, texture: Texture2D = null, tint: Color = Color.WHITE) -> void:
	if node is MeshInstance3D and node.mesh:
		for i in node.mesh.get_surface_count():
			var original := node.mesh.surface_get_material(i) as BaseMaterial3D
			var image := texture
			var color := tint
			if image == null and original:
				image = original.albedo_texture
				color *= original.albedo_color
			node.set_surface_override_material(i,material(image,color))
	for child in node.get_children(): apply(child,texture,tint)
