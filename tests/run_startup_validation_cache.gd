extends SceneTree
## Warm validation caches must never bypass runtime edits or receiving-rig checks.
const Profile = preload("res://features/presentation/animation_profile.gd")
const Appearance = preload("res://features/presentation/character_appearance.gd")
const Base = preload("res://features/presentation/data/ual_animation_profile.tres")
const Rig = preload("res://features/presentation/data/ual_rig.tres")
const Runtime = preload("res://assets/models/ual/runtime_rig.tscn")
const Body = preload("res://assets/models/ual/mannequin_body.res")
const Chest = preload("res://assets/models/ual/chest_fixture.res")
var checks := 0
var failures := 0
var world: Node3D
var receiver: Node3D
var player: AnimationPlayer
var skeleton: Skeleton3D

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+message)

func pose_clip(type: int = Animation.TYPE_POSITION_3D, time: float = 0.0) -> Animation:
	var clip := Animation.new()
	clip.length = 1.0
	var track := clip.add_track(type)
	clip.track_set_path(track,NodePath("Armature/Skeleton3D:root"))
	var value: Variant = Quaternion.IDENTITY if type == Animation.TYPE_ROTATION_3D else Vector3.ONE
	clip.track_insert_key(track,time,value)
	return clip

func warm(profile: Resource, clip: Animation, label: String) -> void:
	for repeat in 3:
		check(profile.validate_clip(clip,player),label+": valid before edit, pass "+str(repeat))

func clip_edits() -> void:
	var profile := Profile.new()
	for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
		var clip := pose_clip(type)
		warm(profile,clip,"Pose track "+str(type))
		var invalid: Variant = Quaternion(0,0,0,0) if type == Animation.TYPE_ROTATION_3D else Vector3(NAN,0,0)
		clip.track_set_key_value(0,0,invalid)
		check(not profile.validate_clip(clip,player),"Cached pose values reject an invalid edit: "+str(type))
	for transition in [-1.0,NAN]:
		var clip := pose_clip()
		warm(profile,clip,"Transition")
		clip.track_set_key_transition(0,0,transition)
		check(not profile.validate_clip(clip,player),"Cached transitions reject negative/nonfinite edits")
	for time_pair in [[0.0,-1e-50],[1.00001-1e-9,1.00001+1e-9]]:
		var clip := pose_clip(Animation.TYPE_POSITION_3D,time_pair[0])
		warm(profile,clip,"Double time boundary")
		var serialized: PackedFloat32Array = clip.get("tracks/0/keys")
		clip.track_set_key_time(0,0,time_pair[1])
		if time_pair[0] > 0:
			check(serialized == clip.get("tracks/0/keys"),"Upper boundary edit is invisible in float32 serialized keys")
		check(not profile.validate_clip(clip,player),"Live double-time check rejects a cached out-of-range time")
	var raw := pose_clip()
	warm(profile,raw,"Raw serialized keys")
	var original: PackedFloat32Array = raw.get("tracks/0/keys")
	var keys := original.duplicate()
	keys[2] = NAN
	raw.set("tracks/0/keys",keys)
	check(not profile.validate_clip(raw,player),"Raw key edit cannot bypass validation through missing changed signal")
	raw.set("tracks/0/keys",original)
	check(profile.validate_clip(raw,player),"Repairing a previously rejected clip succeeds")
	raw.length = 0.1
	raw.track_set_key_time(0,0,0.5)
	check(not profile.validate_clip(raw,player),"Clip duration changes revalidate its keys")
	for target in ["Armature/Skeleton3D:missing",".:root","../Armature/Skeleton3D:root"]:
		var clip := pose_clip()
		warm(profile,clip,"Target")
		clip.track_set_path(0,NodePath(target))
		check(not profile.validate_clip(clip,player),"A warmed clip still checks its receiving target: "+target)
	var added := pose_clip()
	warm(profile,added,"Additional track")
	added.add_track(Animation.TYPE_METHOD)
	check(not profile.validate_clip(added,player),"A new non-pose track rejects after cache warmup")
	var removed := pose_clip()
	warm(profile,removed,"Removed keys")
	removed.track_remove_key(0,0)
	check(not profile.validate_clip(removed,player),"Removing all keys invalidates a warmed track")

func profile_atomicity() -> void:
	check(Base.install(player,Rig),"Install the complete default bank")
	player.play(&"k_walk",0)
	player.seek(0.2,true)
	player.advance(0)
	var before := player.get_animation_list()
	var idle := player.get_animation(&"k_idle")
	var selected := player.assigned_animation
	var clock := player.current_animation_position
	var invalid: Resource = Base.duplicate()
	check(invalid.validate(player,Rig),"Warm a valid complete profile")
	invalid.aliases = invalid.aliases.duplicate()
	invalid.aliases.erase("k_idle")
	check(not invalid.install(player,Rig),"Cached clips cannot admit a profile missing idle")
	invalid = Base.duplicate()
	check(invalid.validate(player,Rig),"Warm profile timing")
	invalid.mantle_source_end_seconds = NAN
	check(not invalid.install(player,Rig),"Cached clips cannot admit invalid profile timing")
	check(player.get_animation_list() == before and player.get_animation(&"k_idle") == idle,"Failed installation preserves the complete active bank")
	check(player.assigned_animation == selected and player.current_animation_position == clock,"Failed installation preserves playback selection and time")
	var other := Runtime.instantiate()
	world.add_child(other)
	var other_player: AnimationPlayer = other.get_node("AnimationPlayer")
	var other_skeleton: Skeleton3D = other.get_node("Armature/Skeleton3D")
	check(Base.validate(other_player,Rig),"A second matching actor can share validated clip data")
	var rest := other_skeleton.get_bone_rest(1)
	rest.origin.x += 0.01
	other_skeleton.set_bone_rest(1,rest)
	check(not Base.validate(other_player,Rig),"A warmed profile still rejects a different actor rest pose")
	check(Base.validate(player,Rig),"Rejected second actor does not poison the first actor")
	other.free()

func rebuilt(mesh: ArrayMesh, arrays: Array) -> void:
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func mesh_edits() -> void:
	var appearance := Appearance.new()
	appearance.configure(skeleton,Body.rig_id)
	var mesh: ArrayMesh = Chest.regions.values()[0].duplicate()
	var original := mesh.surface_get_arrays(0)
	check(appearance.valid_mesh(mesh,Chest.skin),"Warm skinned mesh validation")
	check(appearance.valid_mesh(mesh,Chest.skin),"Reuse matching skinned mesh validation")
	mesh.clear_surfaces()
	check(not appearance.valid_mesh(mesh,Chest.skin),"Clearing a warmed mesh rejects despite no changed signal")
	rebuilt(mesh,original)
	check(appearance.valid_mesh(mesh,Chest.skin),"Rebuilding valid geometry on the same mesh succeeds")
	var arrays := original.duplicate(true)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for influence in 4: weights[influence] = 0.0
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	rebuilt(mesh,arrays)
	check(not appearance.valid_mesh(mesh,Chest.skin),"Rebuilding the same mesh with unnormalized weights rejects")
	check(appearance.valid_geometry(mesh),"Rigid validation may accept geometry without usable skin weights")
	check(not appearance.valid_mesh(mesh,Chest.skin),"Rigid cache success cannot bypass later skin validation")
	rebuilt(mesh,original)
	check(appearance.valid_mesh(mesh,Chest.skin),"Restoring weights permits reuse")
	var short_skin := Skin.new()
	short_skin.set_bind_count(1)
	check(not appearance.valid_mesh(mesh,short_skin),"A different bind count revalidates cached bone indices")
	check(appearance.valid_mesh(mesh,Chest.skin),"Invalid short skin does not poison valid skin validation")
	var replacement: Resource = Body.duplicate()
	replacement.regions = Body.regions.duplicate()
	var torso: ArrayMesh = Body.regions[&"torso"].duplicate()
	replacement.regions[&"torso"] = torso
	check(appearance.set_body(Body) and appearance.equip(Chest),"Working body and coverage fixture installs")
	var before_contact: MeshInstance3D = appearance.contact
	var before_torso: MeshInstance3D = appearance.body[&"torso"]
	check(appearance.compatible(replacement),"Warm a separate valid body replacement")
	var bad_arrays := torso.surface_get_arrays(0)
	weights = bad_arrays[Mesh.ARRAY_WEIGHTS]
	for influence in 4: weights[influence] = 0.0
	bad_arrays[Mesh.ARRAY_WEIGHTS] = weights
	rebuilt(torso,bad_arrays)
	check(not appearance.set_body(replacement),"A warmed replacement with edited weights is rejected")
	check(appearance.contact == before_contact and appearance.body[&"torso"] == before_torso and not before_torso.visible,"Rejected body replacement preserves geometry, contact and armor coverage")
	replacement = Body.duplicate()
	replacement.skin = Body.skin.duplicate()
	check(appearance.compatible(replacement),"Warm a separate skin manifest")
	replacement.skin.set_bind_pose(0,Transform3D(Basis.IDENTITY,Vector3.ONE))
	check(not appearance.set_body(replacement),"Cached mesh acceptance never skips bind transform checks")
	replacement = Body.duplicate()
	replacement.sole_vertices = Body.sole_vertices.duplicate(true)
	check(appearance.compatible(replacement),"Warm sole metadata")
	replacement.sole_vertices["l"] = PackedInt32Array([-1])
	check(not appearance.set_body(replacement),"Nested sole metadata edits are checked after cache warmup")
	check(appearance.contact == before_contact and appearance.body[&"torso"] == before_torso,"Rejected metadata leaves the installed body intact")

func weak_lifetime() -> void:
	var profile := Profile.new()
	var clip := pose_clip()
	check(profile.validate_clip(clip,player),"Short-lived clip validates")
	var clip_ref: WeakRef = weakref(clip)
	clip = null
	check(clip_ref.get_ref() == null,"Validation cache does not keep retired clips alive")
	var appearance := Appearance.new()
	var mesh: ArrayMesh = Chest.regions.values()[0].duplicate()
	check(appearance.valid_mesh(mesh,Chest.skin),"Short-lived mesh validates")
	var mesh_ref: WeakRef = weakref(mesh)
	mesh = null
	check(mesh_ref.get_ref() == null,"Validation cache does not keep retired meshes alive")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	receiver = Runtime.instantiate()
	world.add_child(receiver)
	player = receiver.get_node("AnimationPlayer")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton = receiver.get_node("Armature/Skeleton3D")
	clip_edits()
	profile_atomicity()
	mesh_edits()
	weak_lifetime()
	world.free()
	print("STARTUP VALIDATION CACHE RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
