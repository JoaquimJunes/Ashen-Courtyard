extends Resource
## Model-local supported pose. Hands use physical ledge anchors during contact.
@export var pelvis := Vector3(0,0.6,0)
@export var pitch := -8.0
@export var left_foot := Vector3(-0.16,0.18,-0.1)
@export var right_foot := Vector3(0.16,0.22,-0.12)
@export var knees_out := 0.8
@export var knee_up := 0.5
@export var knee_forward := -0.5
