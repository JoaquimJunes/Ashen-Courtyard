extends RefCounted
## World-scoped candidate enumeration has no per-shape result cap.

static func characters(observer: Node3D, mask: int, source: Node = null) -> Array[Combatant]:
	var result: Array[Combatant] = []
	if not observer.is_inside_tree(): return result
	for body in observer.get_tree().get_nodes_in_group(Combatant.COMBATANTS):
		if body is Combatant and body != source and not body.dead and not body.is_queued_for_deletion() and body.get_world_3d() == observer.get_world_3d() and (body.damage_layer & mask): result.append(body)
	return result

static func fitted(body: Node) -> bool:
	return body is Combatant and body.hitboxes != null and body.hitboxes.enabled

static func ignored_bodies(body: Node) -> Array[RID]:
	var result: Array[RID] = []
	if not is_instance_valid(body): return result
	if body is CollisionObject3D: result.append(body.get_rid())
	var reactions: Variant = body.get("reactions")
	if reactions != null: result.append_array(reactions.driver.collision_exclusions)
	return result

static func ray(observer: Node3D, from: Vector3, to: Vector3, mask: int, source: Node = null) -> Dictionary:
	var ignored := ignored_bodies(source)
	var candidates := characters(observer,mask,source)
	for body in candidates:
		if fitted(body): ignored.append_array(ignored_bodies(body))
	var query := PhysicsRayQueryParameters3D.create(from,to,mask,ignored)
	query.hit_from_inside = true
	var hit := observer.get_world_3d().direct_space_state.intersect_ray(query)
	var distance: float = from.distance_squared_to(hit.position) if not hit.is_empty() else INF
	for body in candidates:
		if not fitted(body): continue
		var candidate: Dictionary = body.hitboxes.ray(from,to)
		if not candidate.is_empty() and from.distance_squared_to(candidate.position) < distance:
			hit = candidate
			distance = from.distance_squared_to(candidate.position)
	return hit

static func clear_line(observer: Node3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from,to,1)
	query.hit_from_inside = true
	return observer.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

static func contact(caster: Combatant, victim: Combatant, origin: Vector3, radius: float, facing := Vector3.ZERO, dot_limit: float = -1.0) -> Dictionary:
	if not is_instance_valid(victim) or victim.dead or victim.is_queued_for_deletion(): return {}
	if not caster.is_inside_tree() or not victim.is_inside_tree() or caster.get_world_3d() != victim.get_world_3d(): return {}
	if fitted(victim):
		for hit in victim.hitboxes.volume_contacts(origin,radius,facing,dot_limit):
			var from: Vector3 = caster.motor.shape_node.global_position if facing != Vector3.ZERO else origin
			if clear_line(caster,from,hit.position): return hit
		return {}
	if facing != Vector3.ZERO:
		if not caster.in_arc(victim,radius,dot_limit): return {}
	elif origin.distance_to(victim.global_position) > radius: return {}
	var target: Vector3 = victim.motor.shape_node.global_position
	var start: Vector3 = caster.motor.shape_node.global_position if facing != Vector3.ZERO else origin
	return {"collider":victim,"position":target} if clear_line(caster,start,target) else {}
