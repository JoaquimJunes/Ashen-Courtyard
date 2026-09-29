extends RefCounted
## Additive pose corrections in world space, after sampling the base animation.
## Never rotates the collision body or camera, and never runs over combat/roll poses.
var rig = preload("res://features/presentation/character_rig.gd").new()
var contact_meshes: Array[MeshInstance3D] = []
var skin_contacts = preload("res://features/presentation/skin_contact_cache.gd").new()
var sole_vertices: Dictionary = {}
var tuning: Resource = preload("res://data/locomotion.tres")
var bank := 0.0
var pitch := 0.0
var twist := 0.0
var slope := 0.0
var previous_yaw := 0.0
var previous_speed := 0.0
var initialized := false
var last_turn_sign := 0.0
var turn_age := 2.0
var s_turn_time := 0.0
var s_turn_boost := 1.0
var anchors: Dictionary = {}
var contacts: Dictionary = {}
var sole_points: Dictionary = {}
var previous_plants: Dictionary = {}
var pelvis_lowering := 0.0
var contact_blend_from: Dictionary = {}
var transition_targets: Dictionary = {}
var contact_blend_duration := 0.0
var contact_blend_time := 0.0
var contact_clip: Animation
var contact_samples: Array[PackedFloat32Array] = []

func prepare_contact_samples(animation: Animation) -> void:
	if contact_clip == animation: return
	contact_clip = animation
	contact_samples = [animation.get_meta("plant_l",PackedFloat32Array()),animation.get_meta("plant_r",PackedFloat32Array())]

func contact_weight(samples: PackedFloat32Array, length: float, time: float) -> float:
	var cursor := fposmod(time/maxf(length,0.001),1.0)*(samples.size()-1)
	var index := int(cursor)
	return lerpf(samples[index],samples[index+1],cursor-index)

func cache_soles(skeleton: Skeleton3D) -> void:
	var mesh: MeshInstance3D = (contact_meshes[0] if not contact_meshes.is_empty() else skeleton.find_children("*","MeshInstance3D",true,false)[0])
	sole_vertices = mesh.get_meta("sole_vertices",{}).duplicate()
	if sole_vertices.is_empty():
		# The legacy Knight has no appearance manifest; generate its support once.
		var names := {}
		for side in ["l","r"]: names[side] = [rig.bone_name("Foot."+side)]
		sole_vertices = skin_contacts.generate_soles(mesh.mesh,mesh.skin,names)
	skin_contacts.configure(mesh,skeleton)
	for side in ["l","r"]:
		var unique := PackedInt32Array()
		var seen := {}
		for source in sole_vertices[side]:
			var vertex: int = skin_contacts.geometry.source_vertices[source]
			if not seen.has(vertex):
				seen[vertex] = true
				unique.append(source)
		# Keep the authored IDs in the resource; only runtime support omits exact
		# position+weight duplicates at UV seams, which never change its extrema.
		sole_vertices[side] = unique
	refresh_soles(skeleton,mesh)

func refresh_soles(skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	skin_contacts.configure(mesh,skeleton)
	skin_contacts.update_palette(Transform3D.IDENTITY)
	for side in ["l","r"]:
		sole_points[side] = skin_contacts.sole_points(rig.bone(skeleton,"Foot."+side),sole_vertices[side])

func reset() -> void:
	bank = 0
	pitch = 0
	twist = 0
	slope = 0
	previous_speed = 0
	initialized = false
	last_turn_sign = 0
	turn_age = 2
	s_turn_time = 0
	s_turn_boost = 1
	reset_contacts()

func reset_contacts() -> void:
	# Foot locks belong only to the current walking/running pose.
	anchors.clear()
	contacts.clear()
	previous_plants.clear()
	contact_blend_from.clear()
	transition_targets.clear()
	contact_blend_duration = 0.0
	contact_blend_time = 0.0
	pelvis_lowering = 0.0

func begin_gait_transition(duration: float) -> void:
	# Contact metadata belongs to the destination clip, but AnimationPlayer still
	# blends its pose from the old clip. Blend their support weights together so
	# changing between walking/running gaits cannot pin a raised swing foot.
	contact_blend_from = previous_plants.duplicate()
	transition_targets.clear()
	for side: String in contacts: transition_targets[side] = contacts[side].ankle
	contact_blend_duration = maxf(0.0,duration)
	contact_blend_time = 0.0

func world_position(skeleton: Skeleton3D, bone: int) -> Vector3:
	return skeleton.global_transform*skeleton.get_bone_global_pose(bone).origin

func rotate_world(skeleton: Skeleton3D, bone: int, rotation: Basis) -> void:
	var world_basis := skeleton.global_basis*skeleton.get_bone_global_pose(bone).basis
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.global_basis
	if parent >= 0: parent_basis *= skeleton.get_bone_global_pose(parent).basis
	skeleton.set_bone_pose_rotation(bone,(parent_basis.inverse()*rotation*world_basis).orthonormalized().get_rotation_quaternion())
	skeleton.force_update_all_bone_transforms()

func solve_leg(skeleton: Skeleton3D, side: String, target: Vector3, forward: Vector3, forward_pole: bool = false) -> void:
	var hip := rig.bone(skeleton,"UpperLeg."+side)
	var knee := rig.bone(skeleton,"LowerLeg."+side)
	var ankle := rig.bone(skeleton,"Foot."+side)
	var a := world_position(skeleton,hip)
	var b := world_position(skeleton,knee)
	var c := world_position(skeleton,ankle)
	var upper := a.distance_to(b)
	var lower := b.distance_to(c)
	var distance := clampf(a.distance_to(target),0.05,upper+lower-0.005)
	var direction := (target-a).normalized()
	if direction.length_squared() < 0.5: return
	var bend := (b-a)-direction*(b-a).dot(direction)
	# Ground adaptation and anticipation need a stable anatomical knee plane.
	# Crossing a projected forward pole flips it when an uphill foot reaches hip
	# height. A fixed lateral axis stays continuous through that raised-foot pose.
	if forward_pole or bend.length() < 0.04:
		bend = forward.cross(Vector3.UP).cross(direction)
	if bend.length_squared() < 0.000001: return
	bend = bend.normalized()
	var along := (upper*upper-lower*lower+distance*distance)/(2*distance)
	var knee_target := a+direction*along+bend*sqrt(maxf(0,upper*upper-along*along))
	rotate_world(skeleton,hip,Basis(Quaternion((b-a).normalized(),(knee_target-a).normalized())))
	b = world_position(skeleton,knee)
	c = world_position(skeleton,ankle)
	rotate_world(skeleton,knee,Basis(Quaternion((c-b).normalized(),(target-b).normalized())))

func clip_contacts(animation: Animation, time: float) -> Dictionary:
	prepare_contact_samples(animation)
	var result := {}
	for side in 2:
		var samples := contact_samples[side]
		if samples.size() < 2: continue
		result["l" if side == 0 else "r"] = contact_weight(samples,animation.length,time)
	return result

func terrain_contacts(animation: Animation, time: float) -> Dictionary:
	# Broaden landing/lift-off on slopes before applying large height offsets.
	# Looking around the source phase anticipates contact without a delayed
	# touchdown; flat-ground swing timing continues to use the original weights.
	var result := clip_contacts(animation,time)
	var span: float = tuning.terrain_contact_blend_seconds
	for step in range(-8,9):
		var fraction := float(step)/8.0
		var influence := 1.0-smoothstep(0.0,1.0,absf(fraction))
		for side in 2:
			var name := "l" if side == 0 else "r"
			if result.has(name): result[name] = maxf(result[name],contact_weight(contact_samples[side],animation.length,time+fraction*span)*influence)
	return result

func update(delta: float, actor: CharacterBody3D, skeleton: Skeleton3D, plants: Dictionary = {}) -> void:
	if sole_points.is_empty(): cache_soles(skeleton)
	var velocity := actor.get_real_velocity()
	var speed := Vector2(velocity.x,velocity.z).length()

	var yaw := actor.global_rotation.y
	if not initialized:
		previous_yaw = yaw
		previous_speed = speed
		initialized = true
	var weight := 1.0-exp(-tuning.response*maxf(delta,0))
	var rate := angle_difference(previous_yaw,yaw)/maxf(delta,0.001)
	var acceleration := (speed-previous_speed)/maxf(delta,0.001)
	previous_yaw = yaw
	previous_speed = speed
	var forward := -actor.global_basis.z
	var normal := actor.get_floor_normal() if actor.is_on_floor() else Vector3.UP
	var grade := atan2(-normal.dot(forward),maxf(normal.y,0.01))
	slope = lerpf(slope,grade,weight)
	var amount := clampf(speed/actor.tuning.sprint_speed,0,1)
	turn_age += delta
	s_turn_time = maxf(0,s_turn_time-delta)
	if absf(rate) > 0.35 and speed > 0.5:
		var turn_sign := signf(rate)
		if last_turn_sign != 0 and turn_sign != last_turn_sign and turn_age < 1.0:
			s_turn_time = 0.65
		last_turn_sign = turn_sign
		turn_age = 0
	s_turn_boost = tuning.s_turn_lean_multiplier if s_turn_time > 0 else 1.0
	bank = lerpf(bank,clampf(rate/4.0,-1,1)*deg_to_rad(tuning.turn_lean_degrees)*amount*s_turn_boost,weight)
	var slope_lean := clampf(slope/deg_to_rad(30),-1,1)*deg_to_rad(tuning.uphill_lean_degrees)
	# Speed sets sustained forward lean; braking briefly brings the torso upright.
	pitch = lerpf(pitch,-slope_lean-deg_to_rad(tuning.running_lean_degrees)*pow(amount,1.4)-clampf(acceleration*0.008,-0.17,0.10),weight)
	var direction := Vector3(velocity.x,0,velocity.z).normalized()
	var turn_ahead := forward.signed_angle_to(direction,Vector3.UP) if speed > 0.3 else 0.0
	twist = lerpf(twist,clampf(turn_ahead,-0.2,0.2),weight)
	var lean := Basis(actor.global_basis.z,bank)*Basis(actor.global_basis.x,pitch)*Basis(Vector3.UP,twist)
	rotate_world(skeleton,rig.bone(skeleton,"Torso"),lean)
	# The rigid torso includes the pelvis; counter-rotate thighs to keep the gait stable.
	if rig.identifier == &"knight_14":
		for side in ["l","r"]: rotate_world(skeleton,rig.bone(skeleton,"UpperLeg."+side),lean.inverse())
	rotate_world(skeleton,rig.bone(skeleton,"Head"),Basis(actor.global_basis.z,-bank*0.65))
	apply_contacts(delta,actor,skeleton,plants)

func apply_contacts(delta: float, actor: CharacterBody3D, skeleton: Skeleton3D, plants: Dictionary = {}) -> void:
	# Enforce the scope here too: preview/direct callers must not plant action feet.
	if not actor.model.foot_placement_enabled():
		reset_contacts()
		return
	if sole_points.is_empty(): cache_soles(skeleton)
	elif not contact_meshes.is_empty(): refresh_soles(skeleton,contact_meshes[0])
	var forward := -actor.global_basis.z
	var terrain_easing: bool = actor.get_floor_normal().y < 0.99 and actor.model.animation.assigned_animation != "crouch/crouch_walk"
	if terrain_easing and not plants.is_empty():
		var animation: AnimationPlayer = actor.model.animation
		plants = terrain_contacts(animation.get_animation(animation.assigned_animation),animation.current_animation_position)
	contacts.clear()
	if not actor.is_on_floor():
		anchors.clear()
		previous_plants.clear()
		contact_blend_from.clear()
		transition_targets.clear()
		pelvis_lowering = 0.0
		return
	contact_blend_time = minf(contact_blend_duration,contact_blend_time+maxf(delta,0.0))
	var contact_blend := smoothstep(0.0,maxf(0.00001,contact_blend_duration),contact_blend_time)
	if contact_blend_time >= contact_blend_duration:
		contact_blend_from.clear()
		transition_targets.clear()
	var targets := {}
	var required_lowering := 0.0
	for side in ["l","r"]:
		var ankle := rig.bone(skeleton,"Foot."+side)
		var foot := world_position(skeleton,ankle)
		var height := foot.y-actor.global_position.y
		var plant_weight: float = plants.get(side,1.0-smoothstep(tuning.plant_height-0.06,tuning.plant_height+0.08,height))
		# Ease into support, then settle fully as the source reaches stance.
		# Partial contact must not leave a nearly planted foot hovering above a ramp.
		if terrain_easing: plant_weight = smoothstep(0.0,1.0,plant_weight)
		if contact_blend_from.has(side): plant_weight = lerpf(contact_blend_from[side],plant_weight,contact_blend)
		var planted := plant_weight > 0.0
		if not planted: anchors.erase(side)
		elif float(previous_plants.get(side,0.0)) <= 0.0: anchors[side] = foot
		previous_plants[side] = plant_weight
		var probe := foot
		if anchors.has(side):
			var anchor: Vector3 = anchors[side]
			var reach := Vector2(anchor.x-foot.x,anchor.z-foot.z).length()
			var strength: float = tuning.foot_plant_strength*plant_weight*(1.0-smoothstep(0.25,0.45,reach))
			probe.x = lerpf(foot.x,anchor.x,strength)
			probe.z = lerpf(foot.z,anchor.z,strength)
		# Include the collision body's support band when the authored foot is
		# raised. A foot-relative ray alone loses the same ramp at swing height,
		# abruptly discarding blended contacts during sprint-to-jog braking.
		var probe_top := Vector3(probe.x,maxf(probe.y,actor.global_position.y)+0.65,probe.z)
		var probe_bottom := Vector3(probe.x,minf(probe.y,actor.global_position.y)-0.85,probe.z)
		var query := PhysicsRayQueryParameters3D.create(probe_top,probe_bottom,1)
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < 0.65:
			anchors.erase(side)
			continue
		var target := probe
		var surface: Vector3 = hit.position
		var sampled_transform := skeleton.global_transform*skeleton.get_bone_global_pose(ankle)
		var correction := Basis(Quaternion.IDENTITY.slerp(Quaternion(Vector3.UP,hit.normal),plant_weight))
		var desired_basis := correction*sampled_transform.basis
		# Measure clearance in the final foot orientation against the slope plane,
		# not world Y before alignment; that otherwise leaves the heel hovering.
		# Blend only the contact offset: adding the full ground height first also
		# drags airborne swing feet downhill and abruptly changes required reach.
		var support := sole_support(side,desired_basis,hit.normal)
		var sole_gap: float = support+hit.normal.dot(target-surface)
		if not is_finite(sole_gap): continue
		target.y += (0.015-sole_gap)*plant_weight/hit.normal.y
		target = clear_sole(target,surface,hit.normal,support)
		# The probe already bounds the terrain search. Do not drop a valid target
		# at a second hard height cutoff: source-clip blends can cross that cutoff
		# for one frame and instantly remove a foot's entire slope correction.
		targets[side] = {"target":target,"basis":desired_basis,"surface":surface,"normal":hit.normal,"plant":plant_weight,"support":support}
		# Keep the authored body height when a long stride exceeds leg reach.
		# The foot can move along its support plane instead of lowering the whole
		# body to reach a distant target. Only an unreachable plane needs a small
		# pelvis correction, solved once for both legs before their individual IK.
		if hit.normal.y < 0.99 or surface.y < actor.global_position.y-0.06:
			var hip := world_position(skeleton,rig.bone(skeleton,"UpperLeg."+side))
			var knee := world_position(skeleton,rig.bone(skeleton,"LowerLeg."+side))
			var reach: float = hip.distance_to(knee)+knee.distance_to(foot)-tuning.leg_reach_reserve
			var plane_distance: float = hit.normal.dot(hip-target)
			required_lowering = maxf(required_lowering,(plane_distance-reach)/hit.normal.y)
	pelvis_lowering = lerpf(pelvis_lowering,clampf(required_lowering,0,tuning.max_pelvis_lowering),1.0-exp(-delta/tuning.pelvis_response_seconds))
	rig.offset_world(skeleton,rig.bone(skeleton,"Body"),Vector3.DOWN*pelvis_lowering)
	skeleton.force_update_all_bone_transforms()
	for side: String in targets:
		var data: Dictionary = targets[side]
		var ankle := rig.bone(skeleton,"Foot."+side)
		# Unplanted feet follow the pelvis; their source swing is still preserved.
		var target: Vector3 = data.target-Vector3.UP*pelvis_lowering*(1.0-data.plant)
		if transition_targets.has(side):
			# Source clips have different stride shapes even at matching phase.
			# Ease the final foot target only during their transition, then fade
			# back to the unchanged gait rather than filtering every swing.
			var filtered: Vector3 = transition_targets[side].lerp(target,1.0-exp(-delta/maxf(tuning.contact_transition_smoothing,0.00001)))
			transition_targets[side] = filtered
			target = filtered.lerp(target,smoothstep(0.65,1.0,contact_blend))
		target = clear_sole(target,data.surface,data.normal,data.support)
		if data.normal.y < 0.99 or data.surface.y < actor.global_position.y-0.06:
			var reachable := reachable_support_target(skeleton,side,target,data.normal)
			# A slope plane ends at an edge. Accept the shortened stride only when
			# a fresh probe confirms that its new position has the same support.
			if reachable.distance_squared_to(target) > 0.000001:
				var query := PhysicsRayQueryParameters3D.create(reachable+Vector3.UP*0.65,reachable-Vector3.UP*0.85,1)
				var support := actor.get_world_3d().direct_space_state.intersect_ray(query)
				if not support.is_empty() and support.normal.dot(data.normal) > 0.99 and absf(data.normal.dot(support.position-data.surface)) < 0.03:
					target = reachable
		solve_leg(skeleton,side,target,forward,true)
		# IK rotates ancestors, so restore the sampled/slope-adjusted ankle angle.
		var current_basis := skeleton.global_basis*skeleton.get_bone_global_pose(ankle).basis
		rotate_world(skeleton,ankle,data.basis*current_basis.inverse())
		var surface: Vector3 = data.surface
		contacts[side] = {"surface":surface,"target":target,"ankle":world_position(skeleton,ankle)}

func reachable_support_target(skeleton: Skeleton3D, side: String, target: Vector3, normal: Vector3) -> Vector3:
	var hip := world_position(skeleton,rig.bone(skeleton,"UpperLeg."+side))
	var knee := world_position(skeleton,rig.bone(skeleton,"LowerLeg."+side))
	var ankle := world_position(skeleton,rig.bone(skeleton,"Foot."+side))
	var reach: float = maxf(0.01,hip.distance_to(knee)+knee.distance_to(ankle)-tuning.leg_reach_reserve)
	if hip.distance_to(target) <= reach: return target
	# Intersect the leg's reach sphere with the target's plane. Clamping within
	# that circle shortens an overlong slope stride without losing sole clearance
	# or dragging a lifted swing foot down to the floor.
	var plane_distance := normal.dot(hip-target)
	var center := hip-normal*plane_distance
	var radius := sqrt(maxf(0.0,reach*reach-plane_distance*plane_distance))
	return center+(target-center).limit_length(radius)


func sole_support(side: String, basis: Basis, normal: Vector3) -> float:
	var lowest := INF
	for point in sole_points[side]: lowest = minf(lowest,normal.dot(basis*point))
	return lowest

func clear_sole(target: Vector3, surface: Vector3, normal: Vector3, support: float) -> Vector3:
	# This support belongs to one pose/orientation/normal. Only translations vary
	# inside apply_contacts; the following tick must calculate fresh support.
	var lowest := support+normal.dot(target-surface)
	if lowest < 0.015: target.y += (0.015-lowest)/normal.y
	return target
