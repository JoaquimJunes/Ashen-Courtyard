extends Resource
## Artist-owned metadata. Keep this and the original glTF beside authoring sources.
@export_file("*.glb", "*.gltf") var source_path := ""
@export_enum("body", "skinned", "rigid") var kind := "skinned"
@export_file("*.res", "*.scn") var output_path := ""
@export_file("*.res") var reference_manifest := "res://assets/models/ual/mannequin_body.res"
@export var rig_id: StringName = &"ual1_65_v1"
@export var skeleton_path: NodePath
## Each region explicitly selects a MeshInstance3D, relative to the imported root.
@export var mesh_regions: Dictionary = {}
@export var slot: StringName = &""
@export var allowed_slots: Array[StringName] = [&"head",&"torso",&"hands",&"legs",&"feet"]
@export var covered_regions: Array[StringName] = []
@export var attachment_bone: StringName = &""
@export var attachment_transform := Transform3D.IDENTITY
## Rigid meshes retain their transforms relative to this node, including no re-centering.
@export var rigid_root: NodePath = NodePath(".")
@export var provenance: Dictionary = {}
