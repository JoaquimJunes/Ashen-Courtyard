extends Resource
const AnimationProfile = preload("res://features/presentation/animation_profile.gd")
@export var role: StringName
@export var free_hands := false
@export var color := Color("72dfe5")
## Null uses the character's installed animation profile.
@export var animations: AnimationProfile
