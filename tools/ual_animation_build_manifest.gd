extends Resource
## Build/test-only source imports. Runtime profiles must never reference this resource.
@export var source_scene: PackedScene
@export var locomotion_clips: Dictionary = {}
@export var combat_clips: Dictionary = {}
@export var action_clips: Dictionary = {}
@export var swimming_clips: Dictionary = {}
