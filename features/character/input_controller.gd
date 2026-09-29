extends RefCounted
## Device input and scripted/AI input produce the same world-space intent.
const Intent = preload("res://features/character/character_intent.gd")
var manual := false
var intent := Intent.new()
var attack_pending := false
var attack_charge := 0.0
var attack_holding := false
const ATTACK_HOLD_SECONDS := 0.15
var stance_down := false
var stance_time := 0.0
var stance_started_lowered := false
var stance_consumed := false
var stance_rearm := false

func reset_stance() -> void:
	stance_down = false
	stance_time = 0
	stance_consumed = false
	stance_rearm = true

func tick_stance(held: bool, delta: float, lowered: bool, threshold: float) -> String:
	if stance_rearm:
		if not held: stance_rearm = false
		return ""
	if held and not stance_down:
		stance_down = true
		stance_time = 0
		stance_consumed = false
		stance_started_lowered = lowered
		if not lowered:
			stance_time = delta
			return "crouch"
	if held:
		stance_time += delta
		if not stance_consumed and stance_time+0.000001 >= threshold:
			stance_consumed = true
			return "crawl"
	elif stance_down:
		stance_down = false
		if stance_started_lowered and not stance_consumed: return "crouch"
	return ""

func attack_press() -> void:
	if attack_pending or attack_holding: return
	attack_pending = true
	attack_charge = 0.0

func attack_release() -> String:
	var action := "cancel_heavy_charge" if attack_holding else ("light" if attack_pending else "")
	reset_attack()
	return action

func tick_attack(delta: float) -> String:
	if not attack_pending and not attack_holding: return ""
	# A release consumed by a menu must not become an attack after resuming.
	if not Input.is_action_pressed("light"):
		var action := "cancel_heavy_charge" if attack_holding else ""
		reset_attack()
		return action
	if attack_holding: return ""
	attack_charge = minf(ATTACK_HOLD_SECONDS,attack_charge+delta)
	if attack_charge+0.000001 < ATTACK_HOLD_SECONDS: return ""
	attack_pending = false
	attack_holding = true
	return "heavy_charge"

func reset_attack() -> void:
	attack_pending = false
	attack_holding = false
	attack_charge = 0.0

func sample(camera_yaw: float, camera_pitch: float = 0.0) -> Intent:
	if manual: return intent
	var axis := Input.get_vector("left","right","forward","back")
	intent.surface_motion = Vector2(axis.x,-axis.y)
	intent.movement = (Basis(Vector3.UP,camera_yaw)*Vector3(axis.x,0,axis.y)).normalized()
	intent.swim_direction = (Basis.from_euler(Vector3(camera_pitch,camera_yaw,0))*Vector3(axis.x,0,axis.y)).limit_length(1.0)
	intent.swim_vertical = Input.get_action_strength("jump")-Input.get_action_strength("crouch")
	intent.sprint = Input.is_action_pressed("sprint")
	intent.crouch_held = Input.is_action_pressed("crouch")
	return intent

func submit(value: Intent) -> void:
	reset_attack()
	manual = true
	intent = value
