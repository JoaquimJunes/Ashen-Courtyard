extends Node3D
const Intent = preload("res://features/character/character_intent.gd")
var player: CharacterBody3D
var water: Area3D
var intent: RefCounted
var ledge: StaticBody3D

func _ready() -> void:
	GameInput.configure()
	water = preload("res://features/swimming/water_volume.tscn").instantiate()
	water.size = Vector3(24,6,20)
	water.show_surface = false
	add_child(water)
	Shapes.solid(self,Vector3(24,0.3,20),Vector3(0,-4.65,0),Color.GRAY)
	Shapes.solid(self,Vector3(6,4.1,20),Vector3(-9,-2.45,0),Color.GRAY)
	ledge = Shapes.solid(self,Vector3(24,5.4,4),Vector3(0,-2.3,-10),Color.GRAY)
	player = preload("res://scenes/player.tscn").instantiate()
	player.position = Vector3(3,-1.1,0)
	player.controller.manual = true
	add_child(player)
	intent = Intent.new()
	player.submit_intent(intent)

func tick(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed+0.00001 < seconds:
		elapsed += float(await player.simulation_stepped)

func reset_at(point: Vector3 = Vector3(3,-1.1,0)) -> void:
	intent = Intent.new()
	player.submit_intent(intent)
	player.combat_enabled = true
	player.reset_for_lab(Transform3D(Basis.IDENTITY,point))
	await tick(0.3)
