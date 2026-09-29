extends RefCounted
## Drives the reviewed forward motion through the actual player's collision body.
enum Phase { PREPARE, AIR, ROLL }
var active := false
var actor: CharacterBody3D
var pose: RefCounted:
	get: return actor.presentation.dive.pose if is_instance_valid(actor) else null
var definition: Resource
var phase := Phase.PREPARE
var time := 0.0
var since_launch := 0.0
var roll_time := 0.0
var segment_start := 0.0
var initial_ground_speed := 0.0
var launch_height := 0.0
var clearance_rise := 0.0

func begin(player: CharacterBody3D) -> void:
	actor = player
	definition = player.actions.active_definition
	active = true
	phase = Phase.PREPARE
	time = 0
	since_launch = 0
	roll_time = 0
	segment_start = 0
	initial_ground_speed = 0
	launch_height = definition.height
	clearance_rise = 0
	actor.motor.launch(0)
	actor.dodge_distance_left = definition.distance
	actor.presentation.dive.begin(actor.model,definition)
	draw(0)

func finish() -> void:
	if not active: return
	active = false
	actor.presentation.dive.finish()
	time = 0
	since_launch = 0
	roll_time = 0
	segment_start = 0
	initial_ground_speed = 0
	launch_height = 0
	clearance_rise = 0
	actor = null
	definition = null

func before_move(delta: float) -> void:
	var distance := 0.0
	if phase == Phase.PREPARE:
		var start := maxf(0,time-definition.preparation*0.5)
		var end := maxf(0,minf(time+delta,definition.preparation)-definition.preparation*0.5)
		distance = definition.preparation_speed*(end*end-start*start)/definition.preparation
		if definition.adaptive_clearance:
			distance = actor.motor.supported_preparation_distance(actor.dodge_dir,distance)
	else:
		since_launch += delta
		actor.invulnerable = since_launch >= definition.immunity_start and since_launch < definition.immunity_end
		if phase == Phase.AIR:
			# Forward intent lasts until real contact, including long cliff falls.
			# Gravity and the motor still decide the trajectory and wall collisions.
			distance = definition.speed*delta
		else:
			var duration := maxf(0.0001,definition.ground_duration-segment_start)
			var start := roll_time-segment_start
			var end := minf(start+delta,duration)
			distance = initial_ground_speed*((end-start)-(end*end-start*start)/(2*duration))
	var speed := distance/maxf(delta,0.00001)
	# The shared resolver applies directed air travel and consumes the budget.
	# This executor only authors the preparation and grounded braking curves.
	actor.actions.request_motion(actor.dodge_dir*speed,actor.dodge_dir*definition.speed,false,
		pow(definition.air_rate,2) if phase == Phase.AIR else 1.0,actor.actions.travel)

func after_move(delta: float) -> void:
	time += delta
	if phase == Phase.PREPARE:
		if not actor.is_on_floor():
			# Walking off during preparation cannot create a midair launch.
			actor.state = actor.State.FREE
			actor.clear_dodge()
			return
		if time >= definition.preparation:
			draw(0)
			actor.presentation.dive.capture_launch()
			phase = Phase.AIR
			time = 0
			select_launch_height()
			actor.motor.launch(sqrt(2*gravity_value()*launch_height))
	elif phase == Phase.AIR:
		if actor.is_on_floor() and actor.velocity.y <= 0:
			actor.presentation.dive.start_transition()
			phase = Phase.ROLL
			time = 0
			segment_start = roll_time
			initial_ground_speed = minf(definition.speed,2*actor.dodge_distance_left/maxf(0.0001,definition.ground_duration-roll_time))
	elif not actor.is_on_floor():
		actor.presentation.dive.start_transition()
		phase = Phase.AIR
		# Stay in the extended/contact pose when falling again, without another launch.
		time = flight_duration()
	else:
		roll_time = minf(definition.ground_duration,roll_time+delta)
	draw(delta)
	actor.dodge_phase = actor.DodgePhase.GROUND_ROLL if phase == Phase.ROLL else actor.DodgePhase.AIRBORNE
	actor.dodge_ground_time = roll_time
	if roll_time >= definition.ground_duration:
		actor.state = actor.State.FREE
		actor.clear_dodge()

func gravity_value() -> float:
	return actor.tuning.gravity*pow(definition.air_rate,2)

func flight_duration() -> float:
	return 2*sqrt(2*gravity_value()*launch_height)/gravity_value()

func select_launch_height() -> void:
	# Decide once, while still grounded. Shared definitions stay read-only and
	# subsequent edges/landings cannot issue another boost or renew immunity.
	if not definition.adaptive_clearance: return
	var surface: Dictionary = actor.motor.probe_dive_surface(actor.dodge_dir,
		minf(definition.clearance_lookahead,actor.dodge_distance_left),
		definition.clearance_max_rise,definition.clearance_probe_spacing)
	var candidate := maxf(definition.height,surface.rise+definition.clearance_margin)
	if candidate > definition.height and actor.motor.has_dive_headroom(candidate):
		launch_height = candidate
		clearance_rise = surface.rise

func draw(delta: float) -> void:
	actor.presentation.dive.sample(phase,roll_time if phase == Phase.ROLL else time,flight_duration(),delta)
