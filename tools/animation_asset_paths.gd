extends RefCounted
## Build-time output paths follow the reviewed identity registry after migration.
## Clip names and animation bindings remain independent from resource filenames.
const REGISTRY := "res://tools/art_asset_identities.json"

static func resolve_path(original: String, registry: Dictionary) -> String:
	if registry.get("version") != 1 or not registry.get("entries") is Array:
		push_error("Invalid animation asset identity registry")
		return ""
	var relative := original.trim_prefix("res://")
	for entry in registry.entries:
		if not entry is Dictionary or not entry.get("aliases") is Array:
			push_error("Invalid animation asset identity record")
			return ""
		if relative == entry.get("original_path") or relative == entry.get("path") or relative in entry.aliases:
			var target: String = entry.get("path", "")
			if not (target.begins_with("assets/animations/") or target.begins_with("art_source/mixamo/")) or ".." in target.split("/") or ":" in target or "\\" in target:
				push_error("Unsafe animation output path")
				return ""
			return "res://" + target
	return original

static func output_path(original: String) -> String:
	if not FileAccess.file_exists(REGISTRY):
		return original
	var data = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	if not data is Dictionary:
		push_error("Cannot read animation asset identity registry")
		return ""
	return resolve_path(original, data)

static func save(resource: Resource, original: String) -> Error:
	var destination := output_path(original)
	if destination.is_empty():
		return ERR_INVALID_DATA
	return ResourceSaver.save(resource, destination)
