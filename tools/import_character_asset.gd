extends SceneTree
## godot --headless --path . --script tools/import_character_asset.gd -- --config res://...tres [--validate-only]
const Config = preload("res://tools/character_asset_import.gd")
const Converter = preload("res://tools/character_asset_converter.gd")
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var config_path := ""
	var validate_only := false
	for index in arguments.size():
		if arguments[index] == "--config" and index+1 < arguments.size(): config_path = arguments[index+1]
		elif arguments[index] == "--validate-only": validate_only = true
	if config_path.is_empty():
		printerr("Usage: --config res://path/import.tres [--validate-only]")
		quit(2)
		return
	var config := load(config_path) as Config
	var converter := Converter.new()
	if not converter.convert(config,validate_only):
		printerr("CHARACTER IMPORT FAILED: "+converter.last_error)
		quit(1)
		return
	print("CHARACTER IMPORT ","VALID" if validate_only else "SAVED",": ",config.source_path," -> ",config.output_path)
	quit()
