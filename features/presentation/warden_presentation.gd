extends RefCounted
const Phase = preload("res://features/abilities/warden_actions.gd").Phase
const BossDefinition = preload("res://features/abilities/boss_attack_definition.gd")
const CUE_SECONDS := 0.12
var actor: CharacterBody3D
var marker: MeshInstance3D

func configure(character: CharacterBody3D) -> void:
	actor = character
	marker = Shapes.orb(actor,0.13,Vector3(0,3.35,0),Color("ffb763"))
	marker.hide()
	for definition in [actor.tuning.combat.boss_combo,actor.tuning.combat.boss_overhead,actor.tuning.combat.boss_lunge]:
		actor.services.prepare_tone(cue_frequency(definition),CUE_SECONDS)
	actor.actions.started.connect(on_started)

func cue_frequency(definition: Resource) -> float:
	return 180.0+definition.pattern*90.0

func on_started(_id: StringName) -> void:
	var definition: Resource = actor.actions.active_definition
	if definition is BossDefinition: actor.services.tone(cue_frequency(definition),CUE_SECONDS)

func prepare() -> void:
	actor.sword.rotation = Vector3.ZERO
	actor.model.rotation.x = 0
	marker.visible = false
	var definition: Resource = actor.actions.active_definition
	if not definition is BossDefinition: return
	var clock: float = actor.actions.timer
	var phase: int = actor.actions.phase
	marker.visible = phase == Phase.TELEGRAPH
	match phase:
		Phase.TELEGRAPH:
			actor.sword.rotation.x = 1.8 if definition.pattern == 1 else 0
			actor.sword.rotation.y = -1.5 if definition.pattern == 0 else 0
			actor.model.rotation.x = -0.12 if definition.pattern == 2 else 0
			marker.scale = Vector3.ONE*(1+clock/maxf(0.001,definition.windup))
		Phase.ATTACK:
			var second: float = definition.active_seconds+definition.combo_gap
			var progress: float = clock if clock < second else clock-second
			actor.sword.rotation.y = lerpf(-1.5,1.5,clampf(progress/definition.active_seconds,0,1))
			if definition.pattern == 1: actor.sword.rotation.x = lerpf(1.8,-0.5,clampf(clock/definition.active_seconds,0,1))
		Phase.RECOVERY: actor.model.rotation.x = 0.12
