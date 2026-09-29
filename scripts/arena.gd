extends Node3D

var player: Combatant
var boss: Combatant
var hud: CanvasLayer
var finished := false
var training := false
var services: Node
const PLAYER_DAMAGE_CUE = [110.0,0.12]
const BOSS_DAMAGE_CUE = [250.0,0.07]

func _ready() -> void:
	services = GameSession.configure_world(self)
	for cue in [PLAYER_DAMAGE_CUE,BOSS_DAMAGE_CUE]: services.prepare_tone(cue[0],cue[1])
	configure_input()
	build_courtyard()
	player = GameSession.create_player(self,services)
	player.motor.teleport(Transform3D(Basis.IDENTITY,Vector3(0,0,7)))
	boss = preload("res://scenes/boss.tscn").instantiate()
	boss.services = services
	add_child(boss)
	boss.motor.teleport(Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,-5)))
	player.target = boss
	boss.target = player
	training = "--training" in OS.get_cmdline_user_args()
	boss.frozen = training
	hud = preload("res://scenes/hud.tscn").instantiate()
	add_child(hud)
	hud.bind(player,boss)
	player.died.connect(func(): end_encounter(false))
	boss.died.connect(func(): end_encounter(true))
	player.damaged.connect(func(): tone(PLAYER_DAMAGE_CUE[0],PLAYER_DAMAGE_CUE[1]))
	boss.damaged.connect(func(): tone(BOSS_DAMAGE_CUE[0],BOSS_DAMAGE_CUE[1]))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func configure_input() -> void:
	GameInput.configure()

func build_courtyard() -> void:
	add_child(preload("res://scenes/dungeon_courtyard.tscn").instantiate())
	var retro := CanvasLayer.new()
	retro.name = "RetroEffects"
	retro.set_script(preload("res://scripts/retro_effects.gd"))
	add_child(retro)

func cast(caster: Combatant, spell: int) -> void:
	# Compatibility adapter for old geometry tests; gameplay casts use the lifecycle.
	var definition: Resource = caster.tuning.bolt if spell == 0 else caster.tuning.burst
	services.cast(caster,definition,caster.get_aim(),preload("res://features/combat/strike_token.gd").new())

func effect(pos: Vector3, color: Color, radius: float) -> void:
	services.effect(pos,color,radius)

func tone(frequency: float, duration: float) -> void:
	services.tone(frequency,duration)

func end_encounter(won: bool) -> void:
	if finished: return
	finished = true
	boss.frozen = true
	player.actions.cancel(&"encounter_end")
	services.clear()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.locked = false
	player.casting_light.hide()
	if not won and not player.reactions.active: create_tween().tween_property(player.model,"rotation:z",PI/2,0.3)
	for child in get_children():
		if child.get_script() == preload("res://scripts/projectile.gd"): child.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_end(won)
