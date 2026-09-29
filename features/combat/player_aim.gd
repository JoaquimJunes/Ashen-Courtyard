extends RefCounted
const Aim = preload("res://features/combat/aim_request.gd")
func sample(actor: CharacterBody3D, camera: Camera3D, target: CharacterBody3D = null) -> Aim:
	var origin := actor.global_position+Vector3.UP*1.2
	if is_instance_valid(target): return Aim.new(origin,target.global_position+Vector3.UP*1.3)
	var end := camera.global_position-camera.global_basis.z*80
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,end,1|actor.services.enemy_mask(actor))
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return Aim.new(origin,hit.position if not hit.is_empty() else end)
