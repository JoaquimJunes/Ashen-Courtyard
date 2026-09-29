extends Resource
## Immutable clips and authored timing. Validate before replacing any live library.
const RigContract = preload("res://features/presentation/animation_rig_contract.gd")
enum Scope { CHARACTER, ACTIONS }
@export var rig_contract: RigContract
@export var scope: Scope = Scope.CHARACTER
@export var rig_identifier: StringName = &"ual1_65_v1"
const REQUIRED_ALIASES = ["k_idle","k_walk","running/jog","running/sprint","crouch/crouch_idle","crouch/crouch_walk","jump/jump_start","jump/jump_air","jump/jump_land","dodge/roll_forward","dodge/roll_left","dodge/roll_right","dodge/roll_back","swimming/swim_idle","swimming/swim_forward"]
const REQUIRED_BONE_ROLES = ["Body","UpperBody","Torso","Head","UpperArm.l","LowerArm.l","Hand.l","UpperArm.r","LowerArm.r","Hand.r","UpperLeg.l","LowerLeg.l","Foot.l","UpperLeg.r","LowerLeg.r","Foot.r"]
var last_error := ""
## Resource notifications omit some key-time/raw-data edits. Guard successful
## key validation with exact serialized arrays, never resource identity alone.
static var validated_keys: Dictionary = {}
const AttackAnimation = preload("res://features/presentation/attack_animation_definition.gd")
const SpellAnimation = preload("res://features/presentation/spell_animation_definition.gd")
@export var native_source_clips: Dictionary = {}
@export var native_locomotion: AnimationLibrary
@export var native_combat: AnimationLibrary
@export var native_actions: AnimationLibrary
@export var native_swimming: AnimationLibrary
@export var retargeted_locomotion: AnimationLibrary
@export var light_attacks: Array[AttackAnimation] = []
@export var heavy_attack: AttackAnimation
@export var sword_idle: StringName
@export var spell_cast: SpellAnimation
@export var mantle_clip: StringName
## Zero uses the complete source; a positive value trims its walking tail.
@export_range(0.0,10.0,0.001) var mantle_source_end_seconds := 0.0
@export var temporary_actions: AnimationLibrary
@export var aliases: Dictionary = {}
@export var temporary_fallbacks: PackedStringArray = []
@export var free_hand_actions: Array[StringName] = [&"bolt",&"burst",&"heal"]

func is_native(alias: String) -> bool:
	var role: StringName = aliases.get(alias,"")
	for library in [native_locomotion,native_combat,native_actions,native_swimming]:
		if library != null and library.has_animation(role): return true
	return false

func clip_for(alias: String) -> Animation:
	var role: StringName = aliases.get(alias,"")
	for library in [native_locomotion,native_combat,native_actions,native_swimming,retargeted_locomotion,temporary_actions]:
		if library != null and library.has_animation(role): return library.get_animation(role)
	return null

func fail(message: String) -> bool:
	last_error = message
	return false

func validate(player: AnimationPlayer = null, rig: Resource = null) -> bool:
	last_error = ""
	if scope not in [Scope.CHARACTER,Scope.ACTIONS] or rig_identifier == &"": return fail("Animation profile needs a scope and rig identifier.")
	if rig_contract == null or rig_contract.rig_identifier != rig_identifier: return fail("Animation profile needs its matching reference rig contract.")
	if not rig_contract.valid(): return fail(rig_contract.last_error)
	if player != null:
		var animation_root := player.get_node_or_null(player.root_node)
		var target: Skeleton3D = animation_root.find_child("Skeleton3D",true,false) if animation_root != null else null
		if target == null or not rig_contract.valid(target): return fail("Animation rig mismatch: "+rig_contract.last_error)
	if rig != null and rig.identifier != rig_identifier: return fail("Animation profile uses a different rig: "+String(rig_identifier))
	if aliases.is_empty(): return fail("Animation profile has no aliases.")
	if scope == Scope.CHARACTER:
		for alias in REQUIRED_ALIASES:
			if not aliases.has(alias): return fail("Character profile is missing required alias: "+alias)
	var checked := {}
	for alias in aliases:
		if not (alias is String or alias is StringName): return fail("Animation aliases must be strings.")
		var parts := String(alias).split("/",true)
		if parts.size() > 2: return fail("Animation aliases use at most one library separator: "+String(alias))
		for part in parts:
			if not part.is_valid_identifier(): return fail("Invalid animation alias: "+String(alias))
		var role = aliases[alias]
		if not (role is String or role is StringName) or String(role).is_empty(): return fail("Animation alias has no valid source role: "+String(alias))
		var matches := 0
		for library in [native_locomotion,native_combat,native_actions,native_swimming,retargeted_locomotion,temporary_actions]:
			if library != null and library.has_animation(role): matches += 1
		if matches != 1: return fail("Animation role must resolve to exactly one library: "+String(role))
		var clip := clip_for(alias)
		if not checked.has(clip):
			if not validate_clip(clip,player): return fail("aliases["+String(alias)+"]: "+last_error)
			checked[clip] = true
	for index in light_attacks.size():
		var attack := light_attacks[index]
		if attack == null: return fail("light_attacks[%s]: missing definition" % index)
		if not attack.valid(self): return fail("light_attacks[%s].%s" % [index,attack.last_error])
	if heavy_attack != null and not heavy_attack.valid(self): return fail("heavy_attack."+heavy_attack.last_error)
	if spell_cast != null and not spell_cast.valid(self): return fail("spell_cast."+spell_cast.last_error)
	for native_alias in [sword_idle,mantle_clip]:
		if native_alias != &"" and not is_native(native_alias): return fail("Missing native action: "+String(native_alias))
	if not is_finite(mantle_source_end_seconds) or mantle_source_end_seconds < 0: return fail("mantle_source_end_seconds: must be finite and nonnegative")
	if mantle_clip != &"" and mantle_source_end_seconds > clip_for(mantle_clip).length: return fail("mantle_source_end_seconds: exceeds mantle_clip duration")
	if rig != null and player != null:
		var root := player.get_node_or_null(player.root_node)
		var skeleton: Skeleton3D = root.find_child("Skeleton3D",true,false) if root != null else null
		if skeleton == null: return fail("Animation root has no skeleton.")
		for role in rig.roles:
			if not (role is String or role is StringName) or not (rig.roles[role] is String or rig.roles[role] is StringName): return fail("Rig roles must map names to bone names.")
		for role in REQUIRED_BONE_ROLES:
			if rig.bone(skeleton,role) < 0: return fail("Rig role has no target bone: "+String(role))
	return true

func validate_clip(clip: Animation, player: AnimationPlayer = null) -> bool:
	if clip == null or not is_finite(clip.length) or clip.length <= 0 or clip.get_track_count() == 0: return fail("Animation must have a positive duration and pose tracks.")
	var root: Node = player.get_node_or_null(player.root_node) if player != null else null
	if player != null and root == null: return fail("Animation root is missing.")
	var id := clip.get_instance_id()
	var cached: Dictionary = validated_keys.get(id,{})
	var reusable: bool = not cached.is_empty() and cached.source.get_ref() == clip and cached.length == clip.length and cached.keys.size() == clip.get_track_count()
	var snapshots: Array = []
	var types := PackedInt32Array()
	var cacheable := true
	var expected: Skeleton3D = root if root is Skeleton3D else (root.find_child("Skeleton3D",true,false) if root != null else null)
	for track in clip.get_track_count():
		var type := clip.track_get_type(track)
		if type not in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]: return fail("Presentation animation contains a non-pose track.")
		var path := clip.track_get_path(track)
		if path.is_absolute() or path.get_subname_count() != 1 or ".." in String(path.get_concatenated_names()).split("/"): return fail("Pose track must target a relative skeleton bone: "+String(path))
		var bone := path.get_subname(0)
		if bone == &"": return fail("Pose track has no bone.")
		if root != null:
			var target := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Skeleton3D
			if target == null or target != expected or target.find_bone(bone) < 0: return fail("Animation target does not exist: "+String(path))
		if clip.track_get_key_count(track) == 0: return fail("Pose track has no keys.")
		var keys: Variant = null if clip.track_is_compressed(track) else clip.get("tracks/%s/keys" % track)
		var exact_keys := keys is PackedFloat32Array
		cacheable = cacheable and exact_keys
		snapshots.append(keys)
		types.append(type)
		if reusable and exact_keys and cached.types[track] == type and cached.keys[track] == keys:
			# Engine key times are doubles, while serialized pose keys use float32.
			# Read times live so a sub-float32 boundary edit cannot reuse validation.
			for key in clip.track_get_key_count(track):
				var time := clip.track_get_key_time(track,key)
				if not is_finite(time) or time < 0 or time > clip.length+0.00001: return fail("Animation key time is outside its clip.")
			continue
		for key in clip.track_get_key_count(track):
			var time := clip.track_get_key_time(track,key)
			if not is_finite(time) or time < 0 or time > clip.length+0.00001: return fail("Animation key time is outside its clip.")
			var transition := clip.track_get_key_transition(track,key)
			if not is_finite(transition) or transition < 0: return fail("Invalid animation key interpolation.")
			var value = clip.track_get_key_value(track,key)
			if type == Animation.TYPE_ROTATION_3D:
				if not value is Quaternion or not value.is_finite() or value.length_squared() < 0.00001: return fail("Invalid animation rotation.")
			elif not value is Vector3 or not value.is_finite(): return fail("Invalid animation transform.")
	if cacheable:
		if not validated_keys.has(id):
			for old_id in validated_keys.keys():
				if validated_keys[old_id].source.get_ref() == null: validated_keys.erase(old_id)
		validated_keys[id] = {"source":weakref(clip),"length":clip.length,"types":types,"keys":snapshots}
	return true

func install(player: AnimationPlayer, rig: Resource = null) -> bool:
	if scope != Scope.CHARACTER: return fail("An action-only profile cannot replace a character profile.")
	if player == null or not validate(player,rig): return false
	var libraries: Dictionary = {}
	for alias in aliases:
		var split := String(alias).rsplit("/",true,1)
		var library_name: StringName = split[0] if split.size() == 2 else ""
		var clip_name: StringName = split[-1]
		if not libraries.has(library_name): libraries[library_name] = AnimationLibrary.new()
		if libraries[library_name].add_animation(clip_name,clip_for(alias)) != OK: return fail("Cannot stage animation alias: "+String(alias))
	var previous := {}
	for name in player.get_animation_library_list(): previous[name] = player.get_animation_library(name)
	for name in previous: player.remove_animation_library(name)
	for name in libraries:
		if player.add_animation_library(name,libraries[name]) != OK:
			for added in player.get_animation_library_list(): player.remove_animation_library(added)
			for original in previous: player.add_animation_library(original,previous[original])
			return fail("Cannot install staged animation libraries.")
	return true
