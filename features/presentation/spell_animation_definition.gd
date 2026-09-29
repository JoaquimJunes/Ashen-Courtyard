extends Resource
## Source poses map onto the existing cast clock; gameplay alone releases spells.
@export var enter_clip: StringName
@export var idle_clip: StringName
@export var shoot_clip: StringName
@export var exit_clip: StringName
@export_range(0.05,0.95) var enter_fraction := 0.7
@export_range(0.05,0.95) var shoot_recovery_fraction := 0.55
@export_range(0,0.2) var blend_in := 0.06
@export_range(0,0.2) var blend_out := 0.08
var last_error := ""

func fail(field: String, reason: String) -> bool:
	last_error = field+": "+reason
	return false

func valid(profile: Resource) -> bool:
	last_error = ""
	for field in ["enter_fraction","shoot_recovery_fraction","blend_in","blend_out"]:
		var value: float = get(field)
		if not is_finite(value) or value < 0: return fail(field,"must be finite and nonnegative")
	for field in ["enter_clip","idle_clip","shoot_clip","exit_clip"]:
		var alias: StringName = get(field)
		if not profile.is_native(alias) or profile.clip_for(alias) == null or profile.clip_for(alias).length <= 0: return fail(field,"must resolve to a nonempty native clip")
	for field in ["enter_fraction","shoot_recovery_fraction"]:
		var value: float = get(field)
		if value <= 0 or value >= 1: return fail(field,"must be strictly between zero and one")
	return true

func sample_time(clock: float, action: Resource, profile: RefCounted) -> Dictionary:
	var enter_end: float = action.windup*enter_fraction
	if clock < enter_end:
		return {"clip":enter_clip,"time":profile.clip_for(enter_clip).length*clampf(clock/maxf(enter_end,0.00001),0,1)}
	if clock < action.windup:
		return {"clip":idle_clip,"time":fposmod(clock-enter_end,profile.clip_for(idle_clip).length)}
	# This source starts with the casting hand extended: its first frame is the
	# release pose, so preparation must not consume any of the shoot animation.
	var since_release: float = clock-action.windup
	var follow_through: float = action.recovery*shoot_recovery_fraction
	if since_release < follow_through:
		return {"clip":shoot_clip,"time":profile.clip_for(shoot_clip).length*clampf(since_release/maxf(follow_through,0.00001),0,1)}
	return {"clip":exit_clip,"time":profile.clip_for(exit_clip).length*clampf((since_release-follow_through)/maxf(action.recovery-follow_through,0.00001),0,1)}
