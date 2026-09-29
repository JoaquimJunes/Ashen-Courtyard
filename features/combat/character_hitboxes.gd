extends RefCounted
## Per-character sensing geometry, separate from the motor's collision capsule.
const Profile = preload("res://features/combat/hitbox_profile.gd")
const Geometry = preload("res://features/combat/hit_geometry.gd")
var actor: CharacterBody3D
var model: Node3D
var profile: Profile
var regions: Array[Dictionary] = []
var enabled := false
var physical_snapshot := false
var breathing_local := Vector3.ZERO
var last_contact := {}
var snapshot_frame := -1
var previous_snapshot_frame := -1
var snapshot_world: Array[Transform3D] = []
var previous_world: Array[Transform3D] = []
var breathing_world := Vector3.ZERO
var breathing_bone := -1

func configure(character: CharacterBody3D, visual: Node3D) -> bool:
	actor = character
	model = visual
	profile = model.rig.hitbox_profile
	if profile == null: return false
	breathing_bone = model.skeleton.find_bone(profile.breathing_bone)
	if profile.rig_id != model.rig.identifier or breathing_bone < 0: return false
	var ids := {}
	for region in profile.regions:
		if region == null or not region.valid() or ids.has(region.id): return false
		var bone: int = model.skeleton.find_bone(region.bone)
		if bone < 0: return false
		ids[region.id] = true
		regions.append({"definition":region,"bone":bone,"transform":Transform3D.IDENTITY})
	enabled = not regions.is_empty()
	actor.motor.teleported.connect(reset)
	reset()
	return enabled

func capture() -> void:
	if not enabled: return
	var frame := Engine.get_physics_frames()
	if snapshot_frame != frame:
		previous_world.assign(snapshot_world)
		previous_snapshot_frame = snapshot_frame
		snapshot_frame = frame
	snapshot_world.resize(regions.size())
	var poses: Array[Transform3D] = []
	var reactions: Variant = actor.get("reactions")
	physical_snapshot = reactions != null and reactions.active and not reactions.getting_up
	if physical_snapshot: poses = reactions.driver.capture_physical_pose()
	else: model.skeleton.force_update_all_bone_transforms()
	var inverse := actor.global_transform.affine_inverse()
	for index in regions.size():
		var region: Dictionary = regions[index]
		var bone: int = region.bone
		var pose: Transform3D = poses[bone] if physical_snapshot else model.skeleton.global_transform*model.skeleton.get_bone_global_pose(bone)
		region.transform = (pose if physical_snapshot else inverse*pose)*region.definition.local_transform
		snapshot_world[index] = pose*region.definition.local_transform
	var head_pose: Transform3D = poses[breathing_bone] if physical_snapshot else model.skeleton.global_transform*model.skeleton.get_bone_global_pose(breathing_bone)
	breathing_local = (head_pose if physical_snapshot else inverse*head_pose)*profile.breathing_offset
	breathing_world = head_pose*profile.breathing_offset
	if previous_world.is_empty():
		previous_world.assign(snapshot_world)
		previous_snapshot_frame = snapshot_frame

func world_transform(region: Dictionary) -> Transform3D:
	return region.transform if physical_snapshot else actor.global_transform*region.transform

func breathing_position() -> Vector3:
	return breathing_world

func query_snapshot() -> Array[Transform3D]:
	# A target already stepped this tick and one still waiting to step expose
	# the same completed world frame. Never move old bones by a new actor frame.
	return previous_world if snapshot_frame >= Engine.get_physics_frames() else snapshot_world

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var hit := {}
	var first := INF
	if not enabled or actor.dead: return hit
	var poses := query_snapshot()
	for index in mini(regions.size(),poses.size()):
		var region: Dictionary = regions[index]
		var inverse := poses[index].affine_inverse()
		var fraction := Geometry.segment(region.definition.shape,inverse*from,inverse*to)
		if fraction >= 0 and fraction < first:
			first = fraction
			hit = {"collider":actor,"position":from.lerp(to,fraction),"fraction":fraction,"region":region.definition.id}
	return hit

func volume_contacts(origin: Vector3, radius: float, facing := Vector3.ZERO, arc_dot: float = -1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not enabled or actor.dead: return result
	var poses := query_snapshot()
	for index in mini(regions.size(),poses.size()):
		var region: Dictionary = regions[index]
		var at := poses[index]
		var point := Geometry.closest_world(region.definition.shape,at,origin)
		var offset := point-origin
		if offset.length_squared() > radius*radius: continue
		var flat := Vector3(offset.x,0,offset.z)
		if facing != Vector3.ZERO and flat.length() >= 0.15 and facing.dot(flat.normalized()) < arc_dot: continue
		result.append({"collider":actor,"position":point,"region":region.definition.id})
	return result

func reset() -> void:
	last_contact.clear()
	snapshot_frame = -1
	previous_snapshot_frame = -1
	snapshot_world.clear()
	previous_world.clear()
	capture()

func unload() -> void:
	enabled = false
	regions.clear()
	last_contact.clear()
	snapshot_world.clear()
	previous_world.clear()
	snapshot_frame = -1
	previous_snapshot_frame = -1
