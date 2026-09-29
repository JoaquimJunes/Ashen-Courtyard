extends Resource
## Authored in bone-local metres. Runtime transforms belong to CharacterHitboxes.
@export var id: StringName
@export var bone: StringName
@export var local_transform := Transform3D.IDENTITY
@export var shape: Shape3D

func valid() -> bool:
	return id != &"" and bone != &"" and local_transform.is_finite() and absf(local_transform.basis.determinant()) > 0.000001 and (shape is BoxShape3D or shape is CapsuleShape3D or shape is SphereShape3D)
