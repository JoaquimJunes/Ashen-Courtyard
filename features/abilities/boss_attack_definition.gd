extends "res://features/abilities/ability_definition.gd"
@export_enum("Combo", "Overhead", "Lunge") var pattern := 0
@export var combo_gap := 0.31
@export var lunge_speed := 12.0
@export var lunge_duration := 0.4
@export var attack_tail := 0.06
@export var reach := 3.3
@export var arc_dot := 0.3
@export var tracking_fraction := 0.65
