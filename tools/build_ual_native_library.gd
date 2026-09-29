extends SceneTree
## CLI-compatible native locomotion build; source keys are verified before replacement.
const Builder = preload("res://tools/ual_animation_builder.gd")
const MANIFEST = preload("res://tools/ual_animation_build_manifest.tres")
const OUTPUT := "res://assets/animations/ual/anim_ual_native_locomotion_library_v01.tres"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var builder := Builder.new()
	var ok := builder.build_library(root,MANIFEST.locomotion_clips,OUTPUT,annotate)
	if not ok: push_error(builder.last_error)
	else: print("UAL NATIVE LIBRARY: preserved and verified ",MANIFEST.locomotion_clips.size()," source clips")
	quit(0 if ok else 1)
func annotate(role: String, clip: Animation, source: Node, player: AnimationPlayer, name: String) -> void:
	if role not in ["walk","jog","sprint","crouch_walk"]: return
	var skeleton: Skeleton3D = source.find_child("Skeleton3D",true,false)
	preload("res://tools/gait_bake.gd").annotate(clip,skeleton,player,name,1.0)
	annotate_sole_contacts(clip,skeleton,player,name)

func annotate_sole_contacts(clip: Animation, skeleton: Skeleton3D, player: AnimationPlayer, name: String) -> void:
	# An ankle can rise while the toes remain in contact. Measure the authored
	# foot surface so that IK releases it after toe-off, without changing a pose.
	var mesh: MeshInstance3D = skeleton.find_children("*","MeshInstance3D",true,false)[0]
	var surfaces: Array = []
	var bind_bones: Array[int] = []
	for bind in mesh.skin.get_bind_count(): bind_bones.append(skeleton.find_bone(mesh.skin.get_bind_name(bind)))
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var feet := {"l": [], "r": []}
		for vertex in vertices.size():
			for side: String in feet:
				var influence := 0.0
				for index in 4:
					var bind_name := mesh.skin.get_bind_name(bones[vertex*4+index])
					if bind_name in ["foot_"+side,"ball_"+side,"ball_leaf_"+side]: influence += weights[vertex*4+index]
				if influence > 0.5: feet[side].append(vertex)
		surfaces.append({"arrays":arrays,"feet":feet})
	var heights := {"l": [], "r": []}
	for sample in 121:
		player.play(name)
		player.seek(sample*clip.length/120.0,true)
		player.advance(0)
		skeleton.force_update_all_bone_transforms()
		var transforms: Array[Transform3D] = []
		for bind in bind_bones.size(): transforms.append(skeleton.get_bone_global_pose(bind_bones[bind])*mesh.skin.get_bind_pose(bind))
		for side: String in heights:
			var lowest := INF
			for surface: Dictionary in surfaces:
				var arrays: Array = surface.arrays
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				for vertex: int in surface.feet[side]:
					var point := Vector3.ZERO
					for index in 4: point += transforms[bones[vertex*4+index]]*vertices[vertex]*weights[vertex*4+index]
					lowest = minf(lowest,point.y)
			heights[side].append(lowest)
	for side: String in heights:
		var floor_height: float = heights[side].min()
		var contacts := PackedFloat32Array()
		for height: float in heights[side]: contacts.append(1.0-smoothstep(floor_height+0.025,floor_height+0.12,height))
		clip.set_meta("plant_"+side,contacts)
