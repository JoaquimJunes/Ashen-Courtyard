extends Resource
## Mesh-only appearance: the owning character supplies the sole animated skeleton.
@export var rig_id: StringName = &"ual1_65_v1"
@export var slot: StringName = &""
@export var covered_regions: Array[StringName] = []
@export var regions: Dictionary = {}
## Rigid geometry may retain source transforms relative to its attachment root.
@export var region_transforms: Dictionary = {}
@export var contact_mesh: ArrayMesh
## Flattened source vertex IDs in contact_mesh, independently declared for each foot.
@export var sole_vertices: Dictionary = {}
@export var skin: Skin
@export var attachment_bone: StringName = &""
@export var attachment_transform := Transform3D.IDENTITY
@export var bone_names: PackedStringArray
@export var parent_names: PackedStringArray
@export var rest_transforms: Array[Transform3D] = []
@export var source_path := ""
@export var source_sha256 := ""
@export var provenance: Dictionary = {}
