extends Node
## Read-only adapter. Bounded history; no queries that change gameplay candidates.
var actor: CharacterBody3D
var events: Array[String] = []
var last_request := "None"
var last_event := ""

func configure(character: CharacterBody3D) -> void:
	actor = character
	actor.actions.request_completed.connect(on_request)
	actor.movement.mode_changed.connect(on_mode)
	actor.actions.cancelled.connect(on_cancel)

func record(value: String) -> void:
	if value == last_event: return
	last_event = value
	events.append("%.2f s  %s" % [Time.get_ticks_msec()/1000.0,value])
	if events.size() > 40: events.pop_front()

func on_request(action: StringName, result: RefCounted) -> void:
	last_request = "%s: %s" % [action,String(result.reason).replace("_"," ")]
	record(last_request)

func on_mode(before: StringName, after: StringName) -> void:
	record("Movement: %s → %s" % [before,after])

func on_cancel(action: StringName, reason: StringName) -> void:
	record("%s cancelled: %s" % [action,reason])

func reset() -> void:
	events.clear()
	last_event = ""
	last_request = "None"

func snapshot() -> Dictionary:
	if not is_instance_valid(actor): return {}
	var candidate: RefCounted = actor.traversal.candidate
	var action := "None" if actor.actions.active_definition == null else String(actor.actions.active_definition.id)
	var velocity: Vector3 = actor.motor.last_result.velocity
	var speed := Vector2(velocity.x,velocity.z).length()
	var support := "Ledge grip" if actor.traversal.attached() else ("Ground" if actor.movement.mode == &"grounded" else "None")
	var explanation: String = String(candidate.reason if candidate != null else actor.traversal.reason).replace("_"," ")
	var movement := [["Posture","Crawling" if actor.crawling.active else ("Crouching" if actor.posture.crouched else "Standing")],["Posture request",String(actor.posture.last_reason)],["Movement",String(actor.movement.mode)],["Action",action],["Speed","%.2f m/s" % speed],["Vertical speed","%.2f m/s" % actor.velocity.y],["Support",support],["Traversal",String(actor.traversal.status)],["Pull-up / grab",explanation],["Last request",last_request],["Position","%.2f, %.2f, %.2f" % [actor.position.x,actor.position.y,actor.position.z]]]
	var phase := "None"
	var rise := 0.0
	if actor.forward_dive.active:
		phase = ["Preparation","Airborne dive","Grounded roll"][actor.forward_dive.phase]
		rise = actor.forward_dive.launch_height
	elif actor.state == actor.State.DODGE:
		phase = "Airborne tuck" if actor.dodge_phase == actor.DodgePhase.AIRBORNE else "Grounded roll"
		rise = actor.actions.active_definition.height
	var actions := [["Ability",action],["Dodge phase",phase],["Ground roll time","%.2f s" % actor.dodge_ground_time],["Travel remaining","%.2f m" % actor.dodge_distance_left],["Selected rise","%.2f m" % rise],["Invulnerable",str(actor.invulnerable)],["Timed landing roll","Success" if actor.landing.roll_succeeded else "No"],["Sprint / reversal brake","%s / %s" % [actor.sprinting,actor.turn_braking]],["Last request",last_request]]
	var contacts := [["Grip", "Attached" if actor.traversal.attached() else "Not attached"],["Pull-up",explanation],["Motor blocked",str(actor.motor.last_result.blocked)]]
	contacts.append(["Head underwater",str(actor.swimming.head_detector.head_submerged)])
	contacts.append(["Breath","%.2f / %.2f s" % [actor.resources.breath,actor.resources.maximum_breath]])
	if actor.hitboxes != null:
		contacts.append(["Fitted regions",str(actor.hitboxes.regions.size())])
		contacts.append(["Last hit",str(actor.hitboxes.last_contact.get("region","None"))])
	if candidate != null:
		contacts.append(["Lip / landing height","%.2f / %.2f m" % [candidate.lip.y,candidate.stand.y]])
		contacts.append(["Pull-up route","Available" if candidate.can_mantle else "Rejected"])
	return {"Movement":movement,"Actions":actions,"Resources":[["Health","%.0f / %.0f" % [actor.health,actor.max_health]],["Stamina","%.0f / %.0f" % [actor.stamina,actor.tuning.stamina_max]],["Mana","%.0f / %.0f" % [actor.mana,actor.tuning.mana_max]],["Flasks",str(actor.flasks)],["Invulnerable",str(actor.invulnerable)],["Last fall","%s / %.2f m / %.1f damage" % [actor.landing.severity,actor.landing.last_height,actor.landing.last_damage]]],"Camera":[["Shoulder","Right" if CameraPreferences.values.side>0 else "Left"],["Field of view","%.0f°" % actor.camera.fov],["Distance","%.2f m" % CameraPreferences.values.distance],["Lock-on",str(actor.locked)]],"Contacts":contacts,"Events":events.duplicate(),"compact":compact()}

func compact() -> String:
	# Live text avoids constructing every inspector tab and copying event history.
	if not is_instance_valid(actor): return ""
	var candidate: RefCounted = actor.traversal.candidate
	var action := "None" if actor.actions.active_definition == null else String(actor.actions.active_definition.id)
	var velocity: Vector3 = actor.motor.last_result.velocity
	var support := "Ledge grip" if actor.traversal.attached() else ("Ground" if actor.movement.mode == &"grounded" else "None")
	var explanation: String = String(candidate.reason if candidate != null else actor.traversal.reason).replace("_"," ")
	return "%s  /  %s  /  %s\n%.2f m/s  ·  %s\nStamina %.0f  ·  Mana %.0f\nLedge: %s" % [actor.movement.mode,"Crawl" if actor.crawling.active else ("Crouch" if actor.posture.crouched else "Stand"),action,Vector2(velocity.x,velocity.z).length(),support,actor.stamina,actor.mana,explanation]
