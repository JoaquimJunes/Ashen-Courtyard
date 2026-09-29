extends RefCounted
## Shared knight-model assembly and damage feedback for player and Warden.
## This model family has a WeaponPivot and locomotion driver; Combatant does not.
var model: Node3D
var sword: Node3D
var flash := 0.0

func configure(actor: CharacterBody3D, scene: PackedScene, locomotion: Resource) -> void:
	model = scene.instantiate()
	actor.add_child(model)
	sword = model.get_node("WeaponPivot")
	model.locomotion.tuning = locomotion
	actor.damage_applied.connect(on_damage)

func on_damage(_request: RefCounted) -> void:
	flash = 0.15

func tick(delta: float, dead: bool) -> void:
	flash = maxf(0,flash-delta)
	model.position.y = 0.06 if flash > 0 else 0.0
	if dead: model.rotation.z = lerpf(model.rotation.z,PI/2,delta*5)

func reset() -> void:
	flash = 0.0
