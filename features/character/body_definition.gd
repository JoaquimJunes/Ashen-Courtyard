extends Resource
## Authored collision settings. The motor's mutable capsule is created per actor.
@export var radius := 0.32
@export var height := 1.8
@export_flags_3d_physics var collision_layer := 2
@export_flags_3d_physics var collision_mask := 1 | 2 | 4
