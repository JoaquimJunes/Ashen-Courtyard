extends SceneTree
## Exact skin-query oracle, shared data ownership and validated weighted foot support.
const Cache = preload("res://features/presentation/skin_contact_cache.gd")
const MODEL = preload("res://scenes/models/ual_mannequin.tscn")
const BODY = preload("res://assets/models/ual/mannequin_body.res")
const FOOT_NAMES = {"l":["foot_l","ball_l","ball_leaf_l"],"r":["foot_r","ball_r","ball_leaf_r"]}
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)

func oracle(model: Node3D, mesh: MeshInstance3D = null) -> PackedVector3Array:
	var skeleton: Skeleton3D = model.skeleton
	skeleton.force_update_all_bone_transforms()
	if mesh == null: mesh = model.contact_meshes[0]
	var palette: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		palette.append(model.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(mesh.skin.get_bind_name(bind)))*mesh.skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for vertex in vertices.size():
			var value := Vector3.ZERO
			for influence in 4:
				var index := vertex*4+influence
				value += palette[joints[index]]*vertices[vertex]*weights[index]
			result.append(value)
	return result

func compare_extrema(model: Node3D, label: String) -> void:
	var points := oracle(model)
	for normal in [Vector3.UP,Vector3.DOWN,Vector3(0.3,0.8,-0.4).normalized()]:
		var expected := INF
		for point in points: expected = minf(expected,normal.dot(point))
		check(absf(model.dodge_skin_min_height(normal)-expected) <= 0.00001,label+": exact skinned support in direction "+str(normal))

func synthetic_support(model: Node3D) -> void:
	var node := MeshInstance3D.new()
	node.skin = Skin.new()
	for bone in ["pelvis","Head"]: node.skin.add_named_bind(bone,Transform3D.IDENTITY)
	var cache := Cache.new()
	for zero_only in [false,true]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(1,2,3),Vector3(-4,-2,1),Vector3(0.25,0.5,-1),Vector3(1,2,3),Vector3(-2,3,4)])
		# Repeated binds, different sums (including zero), and disjoint groups.
		arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,1,0,0, 1,0,0,0, 0,0,0,0, 1,1,0,0])
		arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([0.75,0.5,0,0, 0.25,0.5,0,0, 1,0,0,0, 0,0,0,0, 0.2,0.8,0,0])
		if zero_only: arrays[Mesh.ARRAY_WEIGHTS].fill(0.0)
		node.mesh = ArrayMesh.new()
		node.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS,arrays)
		var points := oracle(model,node)
		for normal in [Vector3.UP,Vector3.DOWN,Vector3(2,-3,0.5),Vector3.ZERO]:
			var expected := INF
			for point in points: expected = minf(expected,normal.dot(point))
			check(absf(cache.minimum(model,node,model.skeleton,normal)-expected) <= 0.00001,"Conservative support with unequal weight sums, repeated/zero binds and signed normals")
		# Bound padding must consider large cancelling terms, not just the result.
		cache.update_palette(Transform3D.IDENTITY)
		cache.palette[0] = Transform3D(Basis(Vector3(100000,99999.98,0),Vector3(100000,100000.01,0),Vector3(0,0,1)),Vector3(50000,50000.02,0))
		for group in cache.geometry.support_groups:
			var normal := Vector3(1,-1,0)
			check(cache.support_bound(group,normal) <= cache.minimum_group(group,normal,INF),"Cancellation cannot make a rejection bound exceed its exact support")
	node.free()

func distributed_body() -> Resource:
	var result := BODY.duplicate()
	var modified := ArrayMesh.new()
	var skin: Skin = result.skin
	for surface in BODY.contact_mesh.get_surface_count():
		var arrays := BODY.contact_mesh.surface_get_arrays(surface)
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for vertex in weights.size()/4:
			for influence in 4:
				var at := vertex*4+influence
				var name := String(skin.get_bind_name(joints[at]))
				if weights[at] <= 0.5 or not (name.begins_with("foot_") or name.begins_with("ball_")): continue
				var source := joints[at]
				var calf := "calf_l" if name.ends_with("_l") else "calf_r"
				var calf_bind := -1
				for bind in skin.get_bind_count():
					if skin.get_bind_name(bind) == calf: calf_bind = bind
				for offset in 4: weights[vertex*4+offset] = 0.0
				joints[vertex*4] = source
				joints[vertex*4+1] = calf_bind
				weights[vertex*4] = 0.5
				weights[vertex*4+1] = 0.5
				break
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_BONES] = joints
		modified.add_surface_from_arrays(BODY.contact_mesh.surface_get_primitive_type(surface),arrays)
	result.contact_mesh = modified
	result.sole_vertices = Cache.generate_soles(modified,skin,FOOT_NAMES)
	return result

func run() -> void:
	var model: Node3D = MODEL.instantiate()
	root.add_child(model)
	model.set_process(false)
	check(Cache.valid_soles(BODY.contact_mesh,BODY.sole_vertices,BODY.skin),"Built-in body contains valid explicit foot support")
	for clip in model.animation.get_animation_list():
		var animation: Animation = model.animation.get_animation(clip)
		for phase in [0.0,0.27,0.63,0.97]:
			model.skeleton.reset_bone_poses()
			model.animation.play(clip)
			model.animation.seek(animation.length*phase,true)
			model.animation.advance(0)
			compare_extrema(model,str(clip)+" "+str(phase))
	var from_rotations: Array[Quaternion] = []
	var from_positions: Array[Vector3] = []
	for bone in model.skeleton.get_bone_count():
		from_rotations.append(model.skeleton.get_bone_pose_rotation(bone))
		from_positions.append(model.skeleton.get_bone_pose_position(bone))
	model.animation.play("running/jog")
	model.animation.seek(0.31,true)
	model.animation.advance(0)
	for bone in model.skeleton.get_bone_count():
		model.skeleton.set_bone_pose_rotation(bone,from_rotations[bone].slerp(model.skeleton.get_bone_pose_rotation(bone),0.37))
		model.skeleton.set_bone_pose_position(bone,from_positions[bone].lerp(model.skeleton.get_bone_pose_position(bone),0.37))
	compare_extrema(model,"Arbitrary transition between authored clips")
	model.rig.offset_world(model.skeleton,model.rig.bone(model.skeleton,"Body"),Vector3.DOWN*0.04)
	model.rotate_bone("Foot.l",Basis(Vector3.RIGHT,deg_to_rad(30)))
	compare_extrema(model,"Additive body lowering and slope foot correction")
	var builds: int = model.skin_contacts.builds
	for repeat in 5: model.dodge_skin_min_height()
	check(model.skin_contacts.builds == builds,"Repeated pose queries reuse binding and geometry data")
	check(model.skin_contacts.geometry.vertices.size() < model.skin_contacts.geometry.source_vertices.size(),"Exact seam duplicates are removed from support queries")
	check(model.skin_contacts.last_scanned_vertices < model.skin_contacts.geometry.vertices.size()/2,"Support rejection avoids scanning most of the body while returning exact extrema")
	var old_transform: Transform3D = model.imported.transform
	model.imported.transform = Transform3D(Basis.from_euler(Vector3(0.2,-0.1,0.3)).scaled(Vector3(1.1,0.8,1.3)),Vector3(0.1,-0.2,0.3))*old_transform
	compare_extrema(model,"Nonuniform imported frame")
	var exact_points := oracle(model)
	for normal in [Vector3(7,-3,2),Vector3.ZERO]:
		var expected := INF
		for point in exact_points: expected = minf(expected,normal.dot(point))
		check(absf(model.dodge_skin_min_height(normal)-expected) <= 0.00001,"Non-unit and zero support directions")
	model.imported.transform = old_transform
	synthetic_support(model)
	model.rotation = Vector3(0.31,0.72,-0.23)
	compare_extrema(model,"Tilted/rotated model")
	var second: Node3D = MODEL.instantiate()
	root.add_child(second)
	second.set_process(false)
	second.dodge_skin_min_height()
	check(model.skin_contacts.geometry == second.skin_contacts.geometry,"Identical assets share immutable support data")
	var palette: Array = model.skin_contacts.palette.duplicate()
	second.animation.play("running/jog")
	second.animation.seek(0.25,true)
	second.animation.advance(0)
	second.dodge_skin_min_height()
	check(model.skin_contacts.palette == palette,"Another actor cannot mutate this pose palette")
	second.free()
	var previous: Node = model.appearance.contact
	for invalid in [{},{"l":PackedInt32Array(),"r":PackedInt32Array([0])},{"l":PackedInt32Array([-1]),"r":PackedInt32Array([0])},{"l":PackedInt32Array([999999]),"r":PackedInt32Array([0])},{"l":PackedInt32Array([0,0]),"r":PackedInt32Array([1])}]:
		var bad := BODY.duplicate()
		bad.sole_vertices = invalid
		check(not model.appearance.set_body(bad),"Malformed/missing foot support rejected")
		check(model.appearance.contact == previous,"Rejected support preserves the working body")
	var forged := BODY.duplicate()
	forged.sole_vertices = BODY.sole_vertices.duplicate(true)
	var invalid_vertex := 0
	while invalid_vertex in BODY.sole_vertices.l or invalid_vertex in BODY.sole_vertices.r: invalid_vertex += 1
	forged.sole_vertices.l = PackedInt32Array([invalid_vertex])
	check(not model.appearance.set_body(forged) and "sole_vertices" in model.appearance.last_error,"In-range non-foot vertices cannot masquerade as sole support")
	check(model.appearance.contact == previous,"Semantically invalid support preserves the working body")
	forged.sole_vertices.l = BODY.sole_vertices.r
	check(not model.appearance.set_body(forged),"Right-foot vertices cannot become left-foot support")
	var distributed := distributed_body()
	var accepted: bool = model.appearance.set_body(distributed)
	check(accepted,"A 0.5 foot / 0.5 calf distribution remains compatible: "+model.appearance.last_error)
	model.locomotion.cache_soles(model.skeleton)
	check(not model.locomotion.sole_points.l.is_empty() and not model.locomotion.sole_points.r.is_empty(),"Distributed skin influences retain both sole supports")
	compare_extrema(model,"Changed weighted contact mesh")
	check(model.skin_contacts.builds == builds+1,"Body contact replacement rebuilds the instance bindings")
	var points := oracle(model)
	var skeleton: Skeleton3D = model.skeleton
	for side in ["l","r"]:
		var ankle: int = model.rig.bone(skeleton,"Foot."+side)
		var frame: Transform3D = model.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(ankle)
		var maximum := 0.0
		var sources: PackedInt32Array = model.locomotion.sole_vertices[side]
		for index in sources.size():
			maximum = maxf(maximum,(frame*model.locomotion.sole_points[side][index]).distance_to(points[sources[index]]))
		check(maximum < 0.00001,"Sole support uses all actual skin influences: "+side)
		check(sources.size() < distributed.sole_vertices[side].size(),"Runtime foot support removes exact seams without changing source metadata")
		for angle in [-30.0,0.0,30.0]:
			var normal := Basis(Vector3.RIGHT,deg_to_rad(angle))*Vector3.UP
			var support: float = model.locomotion.sole_support(side,frame.basis,normal)
			for target in [frame.origin,frame.origin+Vector3(3,0.1,-4),frame.origin+Vector3(-8,-0.05,12)]:
				var surface: Vector3 = target-Vector3(0.1,0.08,0.03)
				var exact := INF
				for source in distributed.sole_vertices[side]:
					var point: Vector3 = frame.affine_inverse()*points[source]
					exact = minf(exact,normal.dot(Transform3D(frame.basis,target)*point-surface))
				var expected: Vector3 = target
				if exact < 0.015: expected.y += (0.015-exact)/normal.y
				check(expected.distance_to(model.locomotion.clear_sole(target,surface,normal,support)) < 0.00001,"Reused foot support matches the full original point cloud after translation")
	model.free()
	print("SKIN CONTACTS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
