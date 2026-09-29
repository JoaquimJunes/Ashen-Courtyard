extends MainLoop
## Reads existing imported scene state without instantiating, importing or saving assets.

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		return
	var sources = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not sources is Dictionary:
		return
	var result := {}
	for source in sources:
		var resource := ResourceLoader.load(sources[source], "", ResourceLoader.CACHE_MODE_IGNORE)
		var names: Array[String] = []
		if resource is PackedScene:
			var state: SceneState = resource.get_state()
			for node in state.get_node_count():
				for property in state.get_node_property_count(node):
					var property_name := String(state.get_node_property_name(node, property))
					if property_name != "libraries" and not property_name.begins_with("libraries/"):
						continue
					var value = state.get_node_property_value(node, property)
					var libraries: Array = value.values() if value is Dictionary else [value]
					for library in libraries:
						if library is AnimationLibrary:
							for clip in library.get_animation_list():
								if not String(clip) in names:
									names.append(String(clip))
			result[source] = {"clip_names": names}
		elif resource is AnimationLibrary:
			result[source] = {"clip_names": resource.get_animation_list()}
	var output := FileAccess.open(arguments[1], FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(result))

func _process(_delta: float) -> bool:
	return true
