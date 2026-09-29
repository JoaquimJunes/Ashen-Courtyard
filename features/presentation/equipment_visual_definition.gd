extends Resource
## Presentation only: no inventory, damage, collision, weight or animation clock.
@export var id: StringName
@export var display_name := ""
@export var visual: PackedScene
@export var placeholder_label := ""
@export var held_socket: StringName
@export var stowed_socket: StringName
@export var held_transform := Transform3D.IDENTITY
@export var stowed_transform := Transform3D.IDENTITY
@export var occupied_hands: Array[StringName] = []
