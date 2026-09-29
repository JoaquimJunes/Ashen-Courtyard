extends RefCounted
## Prepare banks during setup/equipment changes; action execution only reads bindings.
const Binding = preload("res://features/presentation/animation_binding.gd")
var player: AnimationPlayer
var rig: Resource
var default_binding: RefCounted
var bindings: Dictionary = {}
var next_bank := 0
var last_error := ""

func configure(animation: AnimationPlayer, target_rig: Resource, profile: Resource) -> void:
	player = animation
	rig = target_rig
	if profile == null: return # Explicit legacy adapter.
	default_binding = Binding.new()
	default_binding.profile = profile
	for alias in profile.aliases:
		default_binding.names[StringName(alias)] = StringName(alias)
		default_binding.clips[StringName(alias)] = profile.clip_for(alias)
	bindings[profile] = default_binding

func get_binding(profile: Resource) -> RefCounted:
	return default_binding if profile == null else bindings.get(profile)

func prepare(profiles: Array) -> bool:
	last_error = ""
	var staged := {}
	for profile in profiles:
		if profile == null or bindings.has(profile) or staged.has(profile): continue
		if not profile.validate(player,rig):
			last_error = profile.last_error
			return false
		var binding := Binding.new()
		binding.profile = profile
		binding.library_name = StringName("item_bank_%s" % (next_bank+staged.size()))
		if player.has_animation_library(binding.library_name):
			last_error = "Reserved item animation namespace is occupied."
			return false
		var library := AnimationLibrary.new()
		for alias in profile.aliases:
			var local := StringName("clip_%s" % binding.names.size())
			var clip: Animation = profile.clip_for(alias)
			if library.add_animation(local,clip) != OK:
				last_error = "Cannot stage item animation."
				return false
			binding.names[StringName(alias)] = StringName(String(binding.library_name)+"/"+String(local))
			binding.clips[StringName(alias)] = clip
		staged[profile] = {"binding":binding,"library":library}
	var added: Array[StringName] = []
	for profile in staged:
		var entry: Dictionary = staged[profile]
		if player.add_animation_library(entry.binding.library_name,entry.library) != OK:
			for name in added: player.remove_animation_library(name)
			last_error = "Cannot install item animation bank."
			return false
		added.append(entry.binding.library_name)
	for profile in staged: bindings[profile] = staged[profile].binding
	next_bank += staged.size()
	return true

func available(binding: RefCounted, aliases: Array) -> bool:
	if binding == null or not is_instance_valid(player): return false
	for alias in aliases:
		if alias == &"": continue
		var name: StringName = binding.resolved(alias)
		if name == &"" or not player.has_animation(name) or player.get_animation(name) != binding.clip_for(alias): return false
	return true

func prune(profiles: Array, active: RefCounted = null) -> void:
	# Equipment edits are action-gated. A consumed item retains its accepted bank
	# until completion, even when payment removes it from the inventory.
	var retired: Array = []
	for profile in bindings:
		var binding: RefCounted = bindings[profile]
		if binding != default_binding and binding != active and profile not in profiles: retired.append(profile)
	if retired.is_empty(): return
	var selected: StringName = player.assigned_animation
	var clock := player.current_animation_position
	var playing := player.is_playing()
	# Godot retains outgoing blends and assigned names after library removal.
	# Clear them while keeping the displayed transforms and surviving base clock.
	player.stop(true)
	for profile in retired:
		player.remove_animation_library(bindings[profile].library_name)
		bindings.erase(profile)
	player.clear_caches()
	if player.has_animation(selected):
		player.assigned_animation = selected
		if playing: player.play(selected,0)
		player.seek(clock,false)
	else:
		# Select a surviving pose without applying it. The pose driver will blend
		# from its captured skeleton state on the next authoritative tick.
		player.assigned_animation = &"k_idle"

func unload() -> void:
	# The model owns its AnimationPlayer and libraries. Release only this observer.
	bindings.clear()
	default_binding = null
	player = null
	rig = null
