extends RefCounted
## Per-character resolved names, shared immutable clips. Captured by accepted actions.
var profile: Resource
var names: Dictionary = {}
var clips: Dictionary = {}
var library_name: StringName

func clip_for(alias: StringName) -> Animation:
	return clips.get(alias)

func resolved(alias: StringName) -> StringName:
	return names.get(alias,&"")
