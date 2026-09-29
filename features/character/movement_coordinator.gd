extends RefCounted
## Modes are independent of the committed action. Only existing modes are active.
signal mode_changed(previous: StringName, current: StringName)
signal landed(impact_speed: float)
var mode: StringName = &"airborne"
var grace_left := 0.0
var coyote_seconds := 0.10
var airborne_time := 0.0
var jump_consumed := false
var in_flight := false
var support_valid := false
var attachment: RefCounted
var attachment_serial := 0
var ledge_jump := false
# Per-jump reference; never measure obstacle height from the rising body.
var jump_origin_y := 0.0
var water_mode: StringName = &""

func set_water_mode(value: StringName) -> void:
	water_mode = value
	grace_left = 0
	in_flight = false
	airborne_time = 0
	support_valid = false
	jump_consumed = true
	ledge_jump = false
	if attachment == null: change_mode(value)

func clear_water_mode() -> void:
	water_mode = &""
	if mode in [&"surface_swimming",&"underwater_swimming"]:
		in_flight = false
		change_mode(&"airborne")

func attach(value: RefCounted) -> void:
	water_mode = &""
	if attachment != null: attachment.revoke()
	attachment_serial += 1
	value.token = attachment_serial
	attachment = value
	grace_left = 0
	in_flight = false
	support_valid = false
	jump_consumed = true
	ledge_jump = false
	change_mode(&"climbing")

func detach(grounded: bool = false) -> void:
	if attachment != null: attachment.revoke()
	attachment = null
	grace_left = 0
	in_flight = not grounded
	airborne_time = 0
	support_valid = grounded
	jump_consumed = not grounded
	ledge_jump = false
	change_mode(&"grounded" if grounded else &"airborne")

func change_mode(next: StringName) -> void:
	if next == mode: return
	var previous := mode
	mode = next
	mode_changed.emit(previous,mode)

func tick(delta: float) -> void:
	grace_left = maxf(0,grace_left-delta)
	if in_flight: airborne_time += delta

func can_jump() -> bool:
	return not jump_consumed and support_valid and (mode == &"grounded" or grace_left > 0)

func takeoff(feet_y: float) -> void:
	jump_origin_y = feet_y
	ledge_jump = true
	jump_consumed = true
	grace_left = 0
	in_flight = true
	airborne_time = 0

func reset() -> void:
	water_mode = &""
	if attachment != null: attachment.revoke()
	attachment = null
	ledge_jump = false
	jump_origin_y = 0.0
	mode = &"airborne"
	grace_left = 0
	airborne_time = 0
	jump_consumed = false
	in_flight = false
	support_valid = false

func refresh(actor: CharacterBody3D, result: RefCounted = null) -> void:
	if attachment != null: return
	if water_mode != &"":
		change_mode(water_mode)
		return
	var grounded: bool = result.grounded if result != null else actor.is_on_floor()
	var next: StringName = &"grounded" if grounded else &"airborne"
	var touched_down := next == &"grounded" and in_flight
	if next == &"grounded":
		support_valid = true
		grace_left = coyote_seconds
		jump_consumed = false
		in_flight = false
		ledge_jump = false
	else:
		in_flight = true
	if next != mode:
		var previous := mode
		mode = next
		mode_changed.emit(previous,mode)
	if touched_down: landed.emit(actor.motor.impact_down_speed)
