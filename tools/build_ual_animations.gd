extends SceneTree
## Deterministic in-place clips on the unchanged UAL skeleton; never rewrites sources.
const SOURCE = "res://assets/third_party/quaternius/UAL1_Standard.glb"
const OUTPUT = "res://assets/animations/ual/"
const Rig = preload("res://features/presentation/character_rig.gd")
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var mesh: MeshInstance3D
var arrays: Array = []
var bind_bones: Array[int] = []

func _initialize() -> void: run.call_deferred()

func low() -> float:
	var transforms: Array[Transform3D] = []
	for i in mesh.skin.get_bind_count(): transforms.append(skeleton.get_bone_global_pose(bind_bones[i])*mesh.skin.get_bind_pose(i))
	var result := INF
	for surface in arrays:
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = surface[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = surface[Mesh.ARRAY_WEIGHTS]
		for v in vertices.size():
			var point := Vector3.ZERO
			for j in 4: point += transforms[joints[v*4+j]]*vertices[v]*weights[v*4+j]
			result = minf(result,point.y)
	return result

func run() -> void:
	model = load(SOURCE).instantiate()
	root.add_child(model)
	skeleton = model.find_child("Skeleton3D",true,false)
	player = model.find_child("AnimationPlayer",true,false)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	mesh = skeleton.find_children("*","MeshInstance3D",true,false)[0]
	for i in mesh.mesh.get_surface_count(): arrays.append(mesh.mesh.surface_get_arrays(i))
	for i in mesh.skin.get_bind_count(): bind_bones.append(skeleton.find_bone(mesh.skin.get_bind_name(i)))
	var sources := {"idle":"Idle","walk":"Walk","jog":"Jog_Fwd","sprint":"Sprint","jump_start":"Jump_Start","jump_air":"Jump","jump_land":"Jump_Land","crouch_idle":"Crouch_Idle","crouch_walk":"Crouch_Fwd","roll_forward":"Roll","roll_left":"Roll","roll_right":"Roll","roll_back":"Roll"}
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var pelvis := skeleton.find_bone("pelvis")
	var root_bone := skeleton.find_bone("root")
	player.play("Idle")
	player.seek(0,true)
	player.advance(0)
	var idle: Array = []
	for i in skeleton.get_bone_count(): idle.append(skeleton.get_bone_pose(i))
	var reference := skeleton.get_bone_global_rest(pelvis).basis.orthonormalized()
	for clip: String in sources:
		var locomotion := clip in ["jog","sprint"]
		if "--locomotion" in OS.get_cmdline_user_args() and not locomotion: continue
		var original: Animation = player.get_animation(sources[clip])
		var roll := clip.begins_with("roll_")
		var jump := clip.begins_with("jump_")
		var animation := Animation.new()
		animation.length = 1.0 if roll or jump else original.length
		animation.loop_mode = Animation.LOOP_NONE if roll or jump else Animation.LOOP_LINEAR
		for i in skeleton.get_bone_count():
			for type in [Animation.TYPE_ROTATION_3D,Animation.TYPE_POSITION_3D]:
				var track := animation.add_track(type)
				animation.track_set_path(track,NodePath("Armature/Skeleton3D:"+skeleton.get_bone_name(i)))
		var cycle_low := INF
		for sample in 121:
			var phase := sample/120.0
			player.play(sources[clip])
			player.seek(0.0 if clip == "crouch_idle" else phase*original.length,true)
			player.advance(0)
			# Translation on root and pelvis is visual-only, never locomotion travel.
			skeleton.set_bone_pose(root_bone,skeleton.get_bone_rest(root_bone))
			skeleton.force_update_all_bone_transforms()
			var pose := skeleton.global_transform*skeleton.get_bone_global_pose(pelvis)
			pose.origin.x = 0
			pose.origin.z = skeleton.get_bone_global_rest(pelvis).origin.z
			if roll:
				var yaw: float = {"roll_forward":0.0,"roll_left":PI/2,"roll_right":-PI/2,"roll_back":PI}[clip]
				var redirect := Basis(Vector3.UP,yaw)
				pose.basis = redirect*(pose.basis*reference.inverse())*redirect.inverse()*reference
			Rig.set_world_pose(skeleton,pelvis,pose)
			if roll:
				var blend := smoothstep(0,0.1,phase)*(1-smoothstep(0.82,1,phase))
				for i in skeleton.get_bone_count(): skeleton.set_bone_pose(i,idle[i].interpolate_with(skeleton.get_bone_pose(i),blend))
			skeleton.force_update_all_bone_transforms()
			# Feet relative to the actor, including jumps: physics supplies the arc.
			if locomotion:
				cycle_low = minf(cycle_low,low())
			else:
				Rig.offset_world(skeleton,pelvis,Vector3.UP*(0.026-low()))
			for i in skeleton.get_bone_count():
				animation.rotation_track_insert_key(i*2,phase*animation.length,skeleton.get_bone_pose_rotation(i))
				animation.position_track_insert_key(i*2+1,phase*animation.length,skeleton.get_bone_pose_position(i))
		if locomotion:
			# One constant clearance offset preserves the source suspension/bounce.
			var track := pelvis*2+1
			for key in animation.track_get_key_count(track):
				var position: Vector3 = animation.track_get_key_value(track,key)
				position += skeleton.get_bone_global_rest(root_bone).basis.inverse()*Vector3.UP*(0.026-cycle_low)
				animation.track_set_key_value(track,key,position)
			preload("res://tools/gait_bake.gd").annotate(animation,skeleton,player,sources[clip],1.0)
		var error := preload("res://tools/animation_asset_paths.gd").save(animation,OUTPUT+clip+".tres")
		if error != OK:
			push_error("Could not save UAL clip "+clip)
			quit(1)
			return
		print("Baked UAL ",clip)
	model.free()
	quit()
