extends Resource
## Editable immutable rig profile. Semantic roles preserve the presentation contract.
@export var identifier := &"knight_14"
@export var roles: Dictionary = {}
@export var visual_scale := 1.0
@export var visual_yaw := PI
@export var weapon_offset := Vector3(0,0.045,0)
@export var clearance := 0.025
@export var traversal_offset := Vector3.ZERO
@export var grip_offset := Vector2.ZERO
## Minimum torso/head axis lean (radians) for compact crouching on short rigs.
@export var crouch_clearance_lean := 0.0
@export var standing_height := 1.09663
@export var ragdoll_definition: Resource
@export var hitbox_profile: Resource

@export var socket_definitions: Array[Resource] = []

static func ual() -> RefCounted:
	return load("res://features/presentation/data/ual_rig.tres")

func bone_name(role: String) -> String:
	return roles.get(role,"Body" if role in ["Torso","Back"] else role)

func bone(skeleton: Skeleton3D, role: String) -> int:
	return skeleton.find_bone(bone_name(role))

func indices(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for index in skeleton.get_bone_count(): result[skeleton.get_bone_name(index)] = index
	for role in roles: result[role] = bone(skeleton,role)
	return result

static func parent_world(skeleton: Skeleton3D, index: int) -> Transform3D:
	var parent := skeleton.get_bone_parent(index)
	return skeleton.global_transform*skeleton.get_bone_global_pose(parent) if parent >= 0 else skeleton.global_transform

static func set_world_pose(skeleton: Skeleton3D, index: int, pose: Transform3D) -> void:
	var local := parent_world(skeleton,index).affine_inverse()*pose
	skeleton.set_bone_pose_position(index,local.origin)
	skeleton.set_bone_pose_rotation(index,local.basis.orthonormalized().get_rotation_quaternion())

static func offset_world(skeleton: Skeleton3D, index: int, offset: Vector3) -> void:
	skeleton.set_bone_pose_position(index,skeleton.get_bone_pose_position(index)+parent_world(skeleton,index).basis.inverse()*offset)
