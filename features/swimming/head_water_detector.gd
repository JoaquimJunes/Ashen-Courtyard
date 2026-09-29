extends RefCounted
## Mouth/nose immersion, independent of locomotion mode and camera immersion.
signal head_submerged_changed(submerged: bool)
const Water = preload("res://features/swimming/water_volume.gd")
const Geometry = preload("res://features/combat/hit_geometry.gd")
var actor: Node3D
var head_submerged := false
var breathing_position := Vector3.ZERO
var previous := Vector3.ZERO
var has_previous := false
var generation := 0

func configure(character: Node3D) -> void: actor = character

func volumes() -> Array[Node]:
	var result: Array[Node] = []
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return result
	for volume in actor.get_tree().get_nodes_in_group(Water.GROUP):
		if not volume.is_queued_for_deletion() and volume.get_world_3d() == actor.get_world_3d(): result.append(volume)
	return result

func inside(point: Vector3, waters: Array[Node], submerged: bool) -> bool:
	for water in waters:
		var p: Vector3 = water.to_local(point)
		if absf(p.x) <= water.size.x*0.5 and absf(p.z) <= water.size.z*0.5 and p.y >= -water.size.y and p.y <= (0.02 if submerged else -0.02): return true
	return false

func sample(point: Vector3, delta: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not point.is_finite() or delta <= 0: return result
	var owner := generation
	breathing_position = point
	var from := previous if has_previous else point
	previous = point
	has_previous = true
	var waters := volumes()
	var cuts: Array[float] = [0.0,1.0]
	for water in waters:
		for level in [-0.02,0.02]:
			var low: Vector3 = Vector3(-water.size.x*0.5,-water.size.y,-water.size.z*0.5)
			var high: Vector3 = Vector3(water.size.x*0.5,level,water.size.z*0.5)
			var interval := Geometry.box_interval(water.to_local(from),water.to_local(point),low,high)
			if interval.x >= 0: cuts.append_array([interval.x,interval.y])
	cuts.sort()
	for i in range(1,cuts.size()):
		var seconds := (cuts[i]-cuts[i-1])*delta
		if seconds <= 0: continue
		var wet := inside(from.lerp(point,(cuts[i]+cuts[i-1])*0.5),waters,head_submerged)
		set_submerged(wet)
		if owner != generation: return []
		if not result.is_empty() and result[-1].submerged == wet: result[-1].seconds += seconds
		else: result.append({"submerged":wet,"seconds":seconds})
	# Endpoint classification also handles an exact crossing at the end of a tick.
	set_submerged(inside(point,waters,head_submerged))
	if owner != generation: return []
	return result

func set_submerged(value: bool) -> void:
	if value == head_submerged: return
	head_submerged = value
	head_submerged_changed.emit(value)

func reset() -> void:
	generation += 1
	has_previous = false
	previous = Vector3.ZERO
	breathing_position = Vector3.ZERO
	set_submerged(false)
