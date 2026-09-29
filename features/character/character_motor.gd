extends RefCounted
## The only component allowed to move the collision body.
signal motion_reset
signal teleported
var swimming_posture := false
var crawling_posture := false
var crawl_step_height := 0.02
var standing_radius := 0.32
var posture_obstruction := ""
const StepResult = preload("res://features/character/motor_step_result.gd")
var last_result := StepResult.new()
var shape_node: CollisionShape3D
var standing_height := 1.8
var standing_offset := 0.9
var tucked := false
var persistent_posture := false
var actor: CharacterBody3D
var tuning: CombatTuning
var capsule: CapsuleShape3D
var move_velocity := Vector3.ZERO
var turn_braking := false
var allow_step := true
var impact_down_speed := 0.0
var step_control_left := 0.0
var launch_pending := false
var ragdoll_motion := false
var controlled_layer := 0
var controlled_mask := 0
var ragdoll_anchor_offset := Vector3.UP*0.9

func configure(body: CharacterBody3D, settings: CombatTuning, shape: CapsuleShape3D) -> void:
	actor = body
	tuning = settings
	capsule = shape
	standing_height = capsule.height
	standing_radius = capsule.radius
	for child in actor.get_children():
		if child is CollisionShape3D and child.shape == capsule: shape_node = child
	if shape_node != null: standing_offset = shape_node.position.y

func launch(upward_speed: float) -> void:
	step_control_left = 0
	launch_pending = upward_speed > 0
	actor.velocity.y = upward_speed

func is_airborne() -> bool:
	# A launch invalidates cached floor contact before the next collision step.
	return launch_pending or (not actor.is_on_floor() and step_control_left <= 0)

func teleport(at: Transform3D) -> void:
	restore_posture(false)
	last_result = StepResult.new()
	actor.global_transform = at
	actor.velocity = Vector3.ZERO
	move_velocity = Vector3.ZERO
	turn_braking = false
	impact_down_speed = 0
	step_control_left = 0
	launch_pending = false
	motion_reset.emit()
	teleported.emit()
	actor.reset_physics_interpolation()

func face_direction(direction: Vector3, weight: float = 1.0) -> void:
	if direction.length_squared() > 0.01:
		if crawling_posture:
			var facing := actor.global_transform
			facing.basis = Basis(Vector3.UP,lerp_angle(actor.rotation.y,atan2(-direction.x,-direction.z),weight))
			var local := shape_node.transform
			if change_shape_transform(actor.global_transform.affine_inverse()*facing*local,capsule.height,capsule.radius,0,0,true):
				actor.global_basis = facing.basis
				shape_node.transform = local
			return
		var collision_transform := shape_node.global_transform if swimming_posture else Transform3D.IDENTITY
		actor.rotation.y = lerp_angle(actor.rotation.y,atan2(-direction.x,-direction.z),weight)
		# Preserve both world center and orientation until the checked posture sweep;
		# actor yaw must not swing an offset capsule through an adjacent wall.
		if swimming_posture: shape_node.global_transform = collision_transform

func step(delta: float, gravity: float, can_step: bool, centered_gravity: bool = true) -> StepResult:
	last_result = StepResult.new()
	if ragdoll_motion: return last_result
	if swimming_posture: restore_posture()
	if tucked and not persistent_posture: restore_posture()
	var before := actor.global_position
	step_control_left = maxf(0,step_control_left-delta)
	allow_step = can_step
	actor.velocity.y -= gravity*delta*(0.5 if centered_gravity else 1.0)
	if can_step: try_step_up(Vector3(actor.velocity.x,0,actor.velocity.z)*delta)
	var incoming := actor.velocity
	impact_down_speed = 0
	var configured_snap := actor.floor_snap_length
	actor.floor_snap_length = locomotion_snap_length(delta, can_step)
	actor.move_and_slide()
	actor.floor_snap_length = configured_snap
	launch_pending = false
	if actor.is_on_floor(): step_control_left = 0
	for index in actor.get_slide_collision_count():
		var collision := actor.get_slide_collision(index)
		if collision.get_normal().dot(Vector3.UP) >= cos(actor.floor_max_angle):
			impact_down_speed = maxf(impact_down_speed,collision.get_collider_velocity().y-incoming.y)
	if centered_gravity and not actor.is_on_floor(): actor.velocity.y -= gravity*delta*0.5
	if can_step:
		for index in actor.get_slide_collision_count():
			var normal := actor.get_slide_collision(index).get_normal()
			if absf(normal.y) < 0.2:
				var horizontal := Vector3(normal.x,0,normal.z).normalized()
				if move_velocity.dot(horizontal) < 0: move_velocity = move_velocity.slide(horizontal)
	if not actor.is_on_floor():
		# Keep the actual post-collision momentum, including dive/attack impulses.
		move_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)
	last_result.displacement = actor.global_position-before
	last_result.velocity = actor.velocity
	last_result.grounded = actor.is_on_floor()
	last_result.normal = actor.get_floor_normal() if last_result.grounded else Vector3.ZERO
	last_result.impact_speed = impact_down_speed
	return last_result

func shape_query(at: Transform3D, height: float, offset: float) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = standing_radius
	shape.height = maxf(height,2*standing_radius)
	query.shape = shape
	query.transform = at
	query.transform.origin += at.basis*Vector3.UP*offset
	query.collision_mask = actor.collision_mask if not ragdoll_motion else controlled_mask
	query.exclude = [actor.get_rid()]
	query.margin = 0.001
	return query

func posture_clear(at: Transform3D, height: float, offset: float) -> bool:
	var query := shape_query(at,height,offset)
	# Use the exact volume: extra query margin would count ordinary floor contact
	# as an overlap when expanding a feet-anchored crouch capsule.
	query.margin = 0.0
	return actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func posture_path_clear(at: Transform3D, motion: Vector3, height: float, offset: float, contact_tolerance: float = 0.0) -> bool:
	var query := shape_query(at,height,offset)
	# A body pressing a wall can have millimetres of solver contact penetration.
	# This tolerance is only for acquisition queries; movement still sweeps the full shape.
	query.shape.radius -= contact_tolerance
	query.shape.height -= contact_tolerance*2
	query.margin = 0 if contact_tolerance > 0 else query.margin
	var space := actor.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return false
	query.motion = motion
	var fractions := space.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.999

func set_posture(height: float, offset: float, validate: bool = true, persistent: bool = false) -> bool:
	var contained := offset-height*0.5 >= shape_node.position.y-capsule.height*0.5 and offset+height*0.5 <= shape_node.position.y+capsule.height*0.5
	if validate and crawling_posture:
		if not change_shape_transform(Transform3D(Basis.IDENTITY,Vector3.UP*offset),height,standing_radius,0.0,0.0,true): return false
	elif validate and swimming_posture:
		if not set_water_transform(Transform3D(Basis.IDENTITY,Vector3.UP*offset),height,0.0,0.0): return false
	elif validate and not contained and not posture_clear(actor.global_transform,height,offset): return false
	shape_node.basis = Basis.IDENTITY
	swimming_posture = false
	crawling_posture = false
	capsule.radius = standing_radius
	capsule.height = height
	shape_node.position = Vector3.UP*offset
	tucked = not is_equal_approx(height,standing_height) or not is_equal_approx(offset,standing_offset)
	persistent_posture = persistent and tucked
	return true

func swim_shape_query(axis: Vector3, height: float, offset: float, exclusions: Array[RID] = []) -> PhysicsShapeQueryParameters3D:
	var query := shape_query(actor.global_transform,height,offset)
	query.transform.basis = Basis(Quaternion(Vector3.UP,axis.normalized() if not axis.is_zero_approx() else Vector3.UP))
	query.transform.origin = actor.global_position+Vector3.UP*offset
	var ignored: Array[RID] = [actor.get_rid()]
	ignored.append_array(exclusions)
	query.exclude = ignored
	return query

func swim_posture_clear(axis: Vector3, height: float, offset: float, exclusions: Array[RID] = []) -> bool:
	return actor.get_world_3d().direct_space_state.intersect_shape(swim_shape_query(axis,height,offset,exclusions),1).is_empty()

func set_swim_posture(axis: Vector3, height: float, offset: float) -> bool:
	# Entry/recovery compatibility: all changes still use the full transform sweep.
	var query := swim_shape_query(axis,height,offset)
	return set_water_transform(actor.global_transform.affine_inverse()*query.transform,height)

func set_water_transform(local: Transform3D, height: float, delta: float = 0.0, margin: float = 0.001) -> bool:
	if not change_shape_transform(local,height,standing_radius,delta,0.0 if crawling_posture else margin,crawling_posture): return false
	swimming_posture = true
	crawling_posture = false
	return true

func set_crawl_posture(definition: Resource) -> bool:
	if not change_shape_transform(definition.transform(),definition.length,definition.radius,0,0,true): return false
	swimming_posture = false
	crawling_posture = true
	crawl_step_height = definition.max_step
	return true

func crawl_can_rise(height: float) -> bool:
	var at := actor.global_transform
	at.origin.y += 0.002
	return posture_clear(at,height,height*0.5)

func rise_from_crawl(height: float) -> bool:
	if not crawl_can_rise(height): return false
	# Solver resting penetration can be sub-millimetre after physical recovery.
	# Sweep the current full capsule clear of that floor contact before expanding;
	# never shrink collision queries or omit the ceiling to force a posture change.
	if actor.move_and_collide(Vector3.UP*0.002) != null: return false
	return set_posture(height,height*0.5,true,true)

func posture_floor_lift() -> float:
	if not actor.is_on_floor() or ragdoll_motion: return 0.0
	var frame := shape_node.global_transform
	var bottom := frame.origin-Vector3.UP*(capsule.radius+absf(frame.basis.y.y)*(capsule.height*0.5-capsule.radius))
	var floor := floor_probe(bottom+Vector3.UP*0.025,bottom-Vector3.UP*0.025)
	if floor.is_empty() or floor.normal.y < 0.999: return 0.0
	return maxf(0,floor.position.y+0.001-bottom.y)

func clear_posture_floor_contact() -> bool:
	var lift := posture_floor_lift()
	if lift <= 0: return true
	if lift > 0.003: return false
	# Full-body sweep out of solver contact; no query shape shrink or ignored floor.
	return actor.move_and_collide(Vector3.UP*lift) == null

func standing_clear() -> bool:
	var at := actor.global_transform
	at.origin.y += minf(posture_floor_lift(),0.003)
	return posture_clear(at,standing_height,standing_offset)

func change_shape_transform(local: Transform3D, height: float, radius: float, delta: float = 0.0, margin: float = 0.001, feet_anchored: bool = false) -> bool:
	posture_obstruction = ""
	if not local.is_finite(): return false
	if feet_anchored and not clear_posture_floor_contact(): return false
	var query := shape_query(actor.global_transform,height,0)
	query.margin = margin
	var first := shape_node.global_transform
	var target := actor.global_transform*local
	var start := first.basis.orthonormalized().get_rotation_quaternion()
	var finish := target.basis.orthonormalized().get_rotation_quaternion()
	if delta > 0:
		# Releasing a blocked posture must not snap through its deferred rotation.
		var angle := start.angle_to(finish)
		finish = start.slerp(finish,minf(1.0,8.0*delta/maxf(angle,0.00001)))
		target.basis = Basis(finish)
		target.origin = first.origin.move_toward(target.origin,4.0*delta)
	# Bound corner travel for rotation, center translation, and size changes.
	var distance := first.origin.distance_to(target.origin)+start.angle_to(finish)*maxf(height,capsule.height)*0.5+absf(height-capsule.height)+absf(radius-capsule.radius)
	var count := maxi(1,ceili(distance/0.025))
	var space := actor.get_world_3d().direct_space_state
	var bottom := first.origin.y-capsule.radius-absf(first.basis.y.y)*(capsule.height*0.5-capsule.radius)
	var top := maxf(first.origin.y+capsule.radius+absf(first.basis.y.y)*(capsule.height*0.5-capsule.radius),target.origin.y+radius+absf(target.basis.y.y)*(height*0.5-radius))
	var previous_origin := first.origin
	for index in range(1,count+1):
		var weight := float(index)/count
		query.shape.radius = lerpf(capsule.radius,radius,weight)
		query.shape.height = lerpf(capsule.height,height,weight)
		query.transform.basis = Basis(start.slerp(finish,weight))
		var destination := first.origin.lerp(target.origin,weight)
		if feet_anchored:
			# Fold before extending horizontally; do not sweep the long prone capsule
			# through the floor or invent extra headroom during crouch/crawl transitions.
			var vertical_axis := absf(query.transform.basis.y.y)
			var diameter: float = query.shape.radius*2
			if vertical_axis > 0.00001: query.shape.height = minf(query.shape.height,diameter+maxf(0,top-bottom-diameter)/vertical_axis)
			destination.y = maxf(destination.y,bottom+query.shape.radius+vertical_axis*(query.shape.height*0.5-query.shape.radius))
		query.transform.origin = previous_origin
		if feet_anchored:
			# Vertical folding is covered by the bounded full-volume samples above.
			# Casting the already-rotated shape down from the preceding orientation's
			# support height falsely reports ordinary floor contact as an obstruction.
			query.transform.origin.y = destination.y
		query.motion = destination-query.transform.origin
		var fractions := space.cast_motion(query)
		if fractions.size() != 2 or fractions[0] < 0.999:
			posture_obstruction = "sweep %s/%s at %s" % [index,count,query.transform.origin]
			return false
		query.motion = Vector3.ZERO
		query.transform.origin = destination
		var overlaps := space.intersect_shape(query,1)
		if not overlaps.is_empty():
			posture_obstruction = "overlap %s/%s at %s (%s)" % [index,count,destination,overlaps[0].collider.name]
			return false
		previous_origin = destination
	shape_node.global_transform = target
	capsule.radius = radius
	capsule.height = height
	tucked = true
	persistent_posture = true
	return true

func request_water_velocity(value: Vector3) -> void:
	actor.velocity = value if value.is_finite() else Vector3.ZERO
	move_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)
	launch_pending = false
	step_control_left = 0
	impact_down_speed = 0

func step_water(request: RefCounted, delta: float) -> StepResult:
	last_result = StepResult.new()
	if ragdoll_motion or delta <= 0: return last_result
	# Keep the previous safe collider orientation if turning is blocked.
	set_water_transform(request.water_transform,request.water_height,delta)
	request_water_velocity(request.water_velocity)
	var before := actor.global_position
	var saved_mode := actor.motion_mode
	var saved_snap := actor.floor_snap_length
	actor.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	actor.floor_snap_length = 0
	actor.move_and_slide()
	actor.motion_mode = saved_mode
	actor.floor_snap_length = saved_snap
	move_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)
	last_result.displacement = actor.global_position-before
	last_result.velocity = actor.velocity
	last_result.blocked = actor.get_slide_collision_count() > 0
	return last_result

func restore_posture(validate: bool = true) -> bool:
	if shape_node == null: return true
	if validate and tucked and not swimming_posture and not clear_posture_floor_contact(): return false
	if set_posture(standing_height,standing_offset,validate): return true
	# A raised-foot tuck can settle with the logical feet below the support.
	# Expand upward from the actual capsule bottom, preserving its footprint.
	# The expanded shape contains the old shape; checking it covers the change.
	var bottom := shape_node.position.y-capsule.height*0.5
	if swimming_posture:
		bottom = shape_node.position.y-capsule.radius-absf(shape_node.basis.y.y)*(capsule.height*0.5-capsule.radius)
	if tucked and bottom > 0:
		var upright := actor.global_transform
		upright.origin.y += bottom+0.003
		if posture_clear(upright,standing_height,standing_offset):
			if swimming_posture:
				var destination := upright*Transform3D(Basis.IDENTITY,Vector3.UP*standing_offset)
				if not set_water_transform(actor.global_transform.affine_inverse()*destination,standing_height,0.0,0.0): return false
			actor.global_transform = upright
			return set_posture(standing_height,standing_offset,false)
	return false

func step_constrained(target: Vector3, delta: float) -> StepResult:
	last_result = StepResult.new()
	if ragdoll_motion or not target.is_finite() or delta <= 0:
		last_result.blocked = true
		return last_result
	var before := actor.global_position
	var motion := target-before
	# Sweeps, not teleports; a bounded segment also catches narrow obstructions.
	var count := maxi(1,ceili(motion.length()/0.08))
	for index in mini(count,64):
		var hit := actor.move_and_collide(motion/count)
		if hit != null:
			last_result.blocked = true
			last_result.normal = hit.get_normal()
			last_result.grounded = hit.get_normal().dot(Vector3.UP) >= cos(actor.floor_max_angle) and motion.y <= 0
			break
	last_result.displacement = actor.global_position-before
	last_result.velocity = last_result.displacement/delta
	if actor.global_position.distance_to(target) > 0.025: last_result.blocked = true
	actor.velocity = last_result.velocity
	move_velocity = Vector3(actor.velocity.x,0,actor.velocity.z)
	step_control_left = 0
	launch_pending = false
	impact_down_speed = 0
	return last_result

func update_air_movement(direction: Vector3, delta: float) -> void:
	turn_braking = false
	direction = ground_direction(direction)
	# Releasing input does not apply ground friction. Reverse input brakes slowly.
	if direction == Vector3.ZERO: return
	var limit := maxf(tuning.move_speed,move_velocity.length())
	move_velocity = (move_velocity+direction*tuning.movement.air_acceleration*delta).limit_length(limit)

func update_ground_movement(direction: Vector3, top_speed: float, delta: float) -> void:
	direction = ground_direction(direction)
	turn_braking = false
	if direction.is_zero_approx():
		move_velocity = move_velocity.move_toward(Vector3.ZERO,tuning.move_deceleration*delta)
		return
	direction = direction.normalized()
	var current_speed := move_velocity.length()
	if current_speed > 0.1:
		var angle := rad_to_deg(move_velocity.normalized().angle_to(direction))
		# A sharp turn preserves its approach heading until speed is reduced.
		# A reversal requires an almost complete stop before accelerating back.
		var corner_speed := top_speed*tuning.corner_speed_ratio*(1.0-smoothstep(90,180,angle))
		# Allow only floating-point roundoff at the inclusive angle boundary.
		if angle >= tuning.sharp_turn_angle-0.0001 and current_speed > maxf(corner_speed,0.15):
			turn_braking = true
			move_velocity = move_velocity.normalized()*move_toward(current_speed,corner_speed,tuning.sharp_turn_deceleration*delta)
			return
	var response := tuning.move_acceleration if current_speed <= top_speed else tuning.move_deceleration
	var next_speed := move_toward(current_speed,top_speed,response*delta)
	var heading := direction
	if current_speed > 0.1:
		# Rotate the heading without shortening velocity across a turn or diagonal.
		heading = move_velocity/current_speed
		var turn := heading.signed_angle_to(direction,Vector3.UP)
		var max_turn := deg_to_rad(tuning.move_steering_degrees)*delta
		heading = heading.rotated(Vector3.UP,clampf(turn,-max_turn,max_turn)).normalized()
	move_velocity = heading*next_speed

func ground_direction(requested: Vector3) -> Vector3:
	# Ground locomotion and evasive dodges share this controller boundary.
	# Vertical intent belongs to future traversal modes, never dodge propulsion.
	if not is_finite(requested.x) or not is_finite(requested.y) or not is_finite(requested.z): return Vector3.ZERO
	return Vector3(requested.x,0,requested.z).normalized()

func support_clearance(normal: Vector3) -> float:
	# A vertical capsule's bottom sphere touches a slope above its center ray.
	# Callers supply a walkable floor normal and retain their own safety margins.
	return capsule.radius*(1.0/normal.y-1.0)

func locomotion_snap_length(delta: float, can_step: bool) -> float:
	var configured := actor.floor_snap_length
	if not can_step or not actor.is_on_floor() or launch_pending or actor.velocity.y > 0 or step_control_left > 0 or configured <= 0:
		return configured
	var normal := actor.get_floor_normal()
	if normal.y < cos(actor.floor_max_angle): return configured
	var motion := Vector3(actor.velocity.x, 0, actor.velocity.z)*delta
	var drop := maxf(0.0, motion.dot(normal)/normal.y)
	# At 30 Hz a sprint can descend farther along a slope than Godot's default
	# 10 cm snap. Cover this frame's projected descent, within one capsule radius.
	var required := configured+drop
	if required <= configured or required > maxf(configured, capsule.radius): return configured
	# Extend support only over the continuing walkable plane. A ledge, gap or
	# lower platform must retain normal departure instead of attracting the body.
	for fraction: float in [0.5, 1.0]:
		var surface := actor.global_position+motion*fraction-Vector3.UP*(support_clearance(normal)+drop*fraction)
		var hit := floor_probe(surface+Vector3.UP*0.025, surface-Vector3.UP*0.025)
		if hit.is_empty() or hit.normal.y < cos(actor.floor_max_angle) or normal.dot(hit.normal) < cos(deg_to_rad(5)):
			return configured
	return required

func standing_position(surface: Vector3, normal: Vector3, margin: float) -> Vector3:
	return surface+Vector3.UP*(support_clearance(normal)+margin)

func try_step_up(motion: Vector3) -> bool:
	var maximum := crawl_step_height if crawling_posture else tuning.max_step_height
	if not allow_step or not actor.is_on_floor() or motion.length_squared() < 0.000001 or maximum <= 0:
		return false
	var obstacle := KinematicCollision3D.new()
	if not actor.test_move(actor.global_transform,motion,obstacle): return false
	if obstacle.get_normal().y >= cos(actor.floor_max_angle): return false
	# Start at the actual contact so diagonal approaches also probe beyond the lip.
	var probe := obstacle.get_position()+motion.normalized()*0.07
	probe.y = actor.global_position.y
	var query := PhysicsRayQueryParameters3D.create(probe+Vector3.UP*(maximum+0.002),probe+Vector3.UP*0.005,1)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < cos(actor.floor_max_angle): return false
	var rise: float = hit.position.y-actor.global_position.y
	if rise <= 0.005 or rise > maximum+0.0001: return false
	var landing_motion := Vector3(probe.x-actor.global_position.x,0,probe.z-actor.global_position.z)
	# Sweep the entire capsule upward and forward: a foot probe alone misses ceilings.
	# A round capsule rests above an inclined plane, not directly on the ray hit.
	# Its bottom sphere needs r / cos(slope) - r extra vertical clearance.
	# Keep this separate from the ledge height limit (flat steps receive none).
	var slope_clearance := support_clearance(hit.normal)
	# On a downhill diagonal the near edge is higher than the end of the sweep.
	# Cover that part of the landing plane too, while still checking the capsule
	# against ceilings and other obstacles along the complete upward/forward path.
	slope_clearance += maxf(0.0,landing_motion.dot(hit.normal)/hit.normal.y)
	var lift := Vector3.UP*(rise+slope_clearance+0.002)
	if actor.test_move(actor.global_transform,lift): return false
	var raised := actor.global_transform
	raised.origin += lift
	# Check all the way onto the tread, not only this frame's short movement.
	if actor.test_move(raised,landing_motion): return false
	actor.global_position += lift
	actor.velocity.y = 0
	# A successful step briefly lifts the capsule before it settles onto the
	# tread. Keep walking steering during this bounded transition; it is not a jump.
	step_control_left = sqrt(2.0*lift.y/tuning.gravity)+0.05
	return true

func request_horizontal(velocity: Vector3) -> void:
	actor.velocity.x = velocity.x
	actor.velocity.z = velocity.z

func supported_preparation_distance(direction: Vector3, distance: float) -> float:
	# A dive can start at a ledge without its short grounded lean walking off it.
	# This only limits requested preparation travel; it never moves or supports the body.
	var end := actor.global_position+direction*distance
	var hit := floor_probe(end+Vector3.UP*0.05,end-Vector3.UP*0.08)
	return distance if not hit.is_empty() and hit.normal.y >= cos(actor.floor_max_angle) else 0.0

func probe_dive_surface(direction: Vector3, reach: float, max_rise: float, spacing: float) -> Dictionary:
	# Downward rays continue across empty gaps. All heights are relative to takeoff.
	# The raised capsule sweep bounds the scan at tall walls, rather than seeing
	# a tempting landing through a wall. These are read-only world queries.
	var raised := actor.global_transform
	raised.origin.y += max_rise+0.025
	var barrier := KinematicCollision3D.new()
	if actor.test_move(raised,direction*reach,barrier):
		reach = minf(reach,barrier.get_travel().length())
	var result := {"rise":0.0,"distance":0.0}
	var side := direction.cross(Vector3.UP).normalized()
	var steps := maxi(1,ceili(reach/maxf(spacing,0.025)))
	for index in range(1,steps+1):
		var distance := reach*float(index)/steps
		for offset: float in [-capsule.radius*0.75,0.0,capsule.radius*0.75]:
			var at := actor.global_position+direction*distance+side*offset
			var hit := floor_probe(at+Vector3.UP*(max_rise+0.01),at+Vector3.UP*0.015)
			if hit.is_empty() or hit.normal.y < cos(actor.floor_max_angle): continue
			var rise: float = hit.position.y-actor.global_position.y
			if rise > max_rise+0.001 or rise <= result.rise: continue
			# Require space for the whole upright capsule above the sampled surface.
			# A low shelf under a ceiling is not a usable raised landing.
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = actor.global_transform
			query.transform.origin = standing_position(hit.position,hit.normal,0.01)+Vector3.UP*capsule.height*0.5
			query.collision_mask = 1
			query.exclude = [actor.get_rid()]
			if not actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
			result = {"rise":rise,"distance":distance}
	return result

func has_dive_headroom(height: float) -> bool:
	return not actor.test_move(actor.global_transform,Vector3.UP*height)

func floor_probe(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,1,[actor.get_rid()])
	query.hit_from_inside = true
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

func stop() -> void:
	actor.velocity = Vector3.ZERO
	move_velocity = Vector3.ZERO
	turn_braking = false
	launch_pending = false
	motion_reset.emit()

func acquire_ragdoll() -> void:
	if ragdoll_motion: return
	controlled_layer = actor.collision_layer
	controlled_mask = actor.collision_mask
	actor.collision_layer = 0
	actor.collision_mask = 0
	restore_posture(false)
	step_control_left = 0
	ragdoll_motion = true
	launch_pending = false
	motion_reset.emit()

func follow_ragdoll(anchor: Vector3, motion: Vector3) -> void:
	if not ragdoll_motion: return
	actor.global_position = anchor-ragdoll_anchor_offset
	actor.velocity = motion
	move_velocity = Vector3.ZERO

func ragdoll_recovery_location(anchor: Vector3, exclusions: Array[RID] = []) -> Dictionary:
	# Bounded, local candidates. Never stand through ceilings or teleport through walls.
	for offset: Vector3 in [Vector3.ZERO,Vector3(0.35,0,0),Vector3(-0.35,0,0),Vector3(0,0,0.35),Vector3(0,0,-0.35)]:
		var point := anchor+offset
		var floor := floor_probe(point+Vector3.UP*0.3,point-Vector3.UP*1.5)
		if floor.is_empty() or floor.normal.y < cos(actor.floor_max_angle): continue
		if not floor_probe(anchor,point).is_empty(): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.collision_mask = controlled_mask
		query.exclude = exclusions
		var feet := standing_position(floor.position,floor.normal,0.03)
		query.transform = Transform3D(Basis.IDENTITY,feet+Vector3.UP*standing_offset)
		if not actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		return {"transform":Transform3D(actor.global_basis,feet),"normal":floor.normal}
	return {}

func release_ragdoll() -> void:
	if not ragdoll_motion: return
	actor.collision_layer = controlled_layer
	actor.collision_mask = controlled_mask
	ragdoll_motion = false
	stop()

func ragdoll_crawl_location(anchor: Vector3, definition: Resource, exclusions: Array[RID]) -> Dictionary:
	for offset: Vector3 in [Vector3.ZERO,Vector3(0.35,0,0),Vector3(-0.35,0,0),Vector3(0,0,0.35),Vector3(0,0,-0.35)]:
		var point := anchor+offset
		var floor := floor_probe(point+Vector3.UP*0.3,point-Vector3.UP*1.5)
		if floor.is_empty() or floor.normal.y < 0.99 or not floor_probe(anchor,point).is_empty(): continue
		var at := Transform3D(actor.global_basis,floor.position+Vector3.UP*0.004)
		var query := shape_query(at,definition.length,0)
		query.shape.radius = definition.radius
		query.shape.height = definition.length
		query.transform = at*definition.transform()
		var ignored: Array[RID] = exclusions.duplicate()
		ignored.append(actor.get_rid())
		query.exclude = ignored
		if actor.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return {"transform":at,"normal":floor.normal}
	return {}

func restore_crawling_from_ragdoll(at: Transform3D, definition: Resource) -> void:
	# Caller has validated this entire shape while excluding its own physical bones.
	# Never enable a standing capsule in the low recovery location.
	actor.global_transform = at
	shape_node.transform = definition.transform()
	capsule.radius = definition.radius
	capsule.height = definition.length
	crawling_posture = true
	swimming_posture = false
	tucked = true
	persistent_posture = true
	crawl_step_height = definition.max_step
	last_result = StepResult.new()
	step_control_left = 0
	release_ragdoll()
	actor.apply_floor_snap()
	teleported.emit()
	actor.reset_physics_interpolation()

func restore_from_ragdoll(at: Transform3D) -> void:
	release_ragdoll()
	teleport(at)
	actor.apply_floor_snap()
