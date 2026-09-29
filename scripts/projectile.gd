extends Node3D
var direction := Vector3.FORWARD
var speed := 18.0
var damage := 32.0
var source: CollisionObject3D
var life := 3.0
var strike_id := ""
var strike: RefCounted
var services: Node
var hit_mask := 1|4

func _ready() -> void:
	if services == null and is_instance_valid(source) and source is Combatant: services = source.services
	if strike == null:
		strike = preload("res://features/combat/strike_token.gd").new()
		strike.id = StringName(strike_id)
	Shapes.orb(self,0.18,Vector3.ZERO,Color("72dfe5"))

func _physics_process(delta: float) -> void:
	var next := global_position+direction*speed*delta
	var hit := preload("res://features/combat/damage_queries.gd").ray(self,global_position,next,hit_mask,source if is_instance_valid(source) else null)
	if not hit.is_empty():
		var receiver := preload("res://features/combat/damage_receiver.gd").resolve(hit.collider)
		if receiver != null:
			var request := preload("res://features/combat/damage_request.gd").new(damage,StringName(strike_id),strike)
			request.source = source if is_instance_valid(source) else null
			request.damage_type = &"magic"
			request.impact = hit.position
			request.region = hit.get("region",&"")
			receiver.receive_damage(request)
		if is_instance_valid(services): services.effect(hit.position,Color("72dfe5"),0.6)
		queue_free()
	else: global_position = next
	life -= delta
	if life <= 0: queue_free()
