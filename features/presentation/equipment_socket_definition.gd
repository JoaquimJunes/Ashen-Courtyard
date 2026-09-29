extends Resource
## A named rigid attachment frame, local to a bone on the character skeleton.
@export var id: StringName
@export var bone_name: StringName
@export var local_transform := Transform3D.IDENTITY
