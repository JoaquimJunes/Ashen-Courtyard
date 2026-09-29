extends Resource
## Source-time landmarks. Gameplay owns all action phase durations.
@export var clip: StringName
@export var recovery_clip: StringName
@export var strike_start := 0.0
@export var strike_end := 0.0
@export_range(0,0.2) var blend_in := 0.06
@export_range(0,0.2) var blend_out := 0.08
var last_error := ""

func fail(field: String, reason: String) -> bool:
	last_error = field+": "+reason
	return false

func valid(profile: Resource) -> bool:
	last_error = ""
	for field in ["strike_start","strike_end","blend_in","blend_out"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0: return fail(field,"must be finite and nonnegative")
	var attack: Animation = profile.clip_for(clip)
	if attack == null or not profile.is_native(clip): return fail("clip","must resolve to a native attack")
	if attack.loop_mode != Animation.LOOP_NONE: return fail("clip","attack must not loop")
	if strike_start <= 0: return fail("strike_start","must be after the first frame")
	if strike_end <= strike_start or strike_end > attack.length: return fail("strike_end","must follow strike_start within the clip")
	# Some source attacks contain their own recovery in the same authored clip.
	if recovery_clip == &"":
		return true if strike_end < attack.length else fail("strike_end","must leave an authored recovery tail")
	var recovery: Animation = profile.clip_for(recovery_clip)
	if recovery == null or not profile.is_native(recovery_clip): return fail("recovery_clip","must resolve to a native recovery")
	return true if recovery.loop_mode == Animation.LOOP_NONE else fail("recovery_clip","recovery must not loop")

func sample_time(clock: float, action: Resource, attack_length: float, recovery_length: float) -> Dictionary:
	if clock < action.windup:
		return {"clip":clip,"time":strike_start*clampf(clock/maxf(action.windup,0.00001),0,1)}
	if clock < action.windup+action.active_seconds:
		return {"clip":clip,"time":lerpf(strike_start,strike_end,clampf((clock-action.windup)/maxf(action.active_seconds,0.00001),0,1))}
	# Finish the authored follow-through, then the matching return-to-guard clip.
	var tail := attack_length-strike_end
	if recovery_clip == &"":
		return {"clip":clip,"time":lerpf(strike_end,attack_length,clampf((clock-action.windup-action.active_seconds)/maxf(action.recovery,0.00001),0,1))}
	if action.chain_after_active >= 0:
		var follow_through := minf(action.chain_after_active,action.recovery)
		var since_strike: float = maxf(0,clock-action.windup-action.active_seconds)
		if since_strike < follow_through:
			return {"clip":clip,"time":lerpf(strike_end,attack_length,since_strike/maxf(follow_through,0.00001))}
		return {"clip":recovery_clip,"time":recovery_length*clampf((since_strike-follow_through)/maxf(action.recovery-follow_through,0.00001),0,1)}
	var elapsed := clampf((clock-action.windup-action.active_seconds)/maxf(action.recovery,0.00001),0,1)*(tail+recovery_length)
	if elapsed < tail: return {"clip":clip,"time":strike_end+elapsed}
	return {"clip":recovery_clip,"time":minf(elapsed-tail,recovery_length)}
