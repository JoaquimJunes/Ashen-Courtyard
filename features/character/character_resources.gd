extends RefCounted
signal health_changed(current: float, maximum: float)
signal breath_changed(current: float, maximum: float)
var breath := 20.0
var maximum_breath := 20.0
var health := 100.0
var maximum_health := 100.0
var stamina := 100.0
var mana := 100.0
## Compatibility for old callers. Player charges have one owner: Inventory.
var item_charges: RefCounted
var _legacy_flasks := 3
var flasks: int:
	get: return item_charges.get_flasks() if item_charges != null else _legacy_flasks
	set(value):
		if item_charges != null: item_charges.set_flasks(value)
		else: _legacy_flasks = value
var stamina_wait := 0.0
var mana_wait := 0.0
var definition: Resource

func configure(settings: Resource, hp: float) -> void:
	definition = settings
	maximum_health = hp
	reset()

func reset() -> void:
	reset_breath()
	health = maximum_health
	stamina = definition.stamina_max
	mana = definition.mana_max
	if item_charges != null: item_charges.reset_flasks()
	else: flasks = 3
	stamina_wait = 0
	mana_wait = 0
	health_changed.emit(health,maximum_health)

func reset_breath() -> void:
	breath = maximum_breath
	breath_changed.emit(breath,maximum_breath)

func tick_breath(delta: float, submerged: bool, refill_seconds: float) -> float:
	var before := breath
	var empty_seconds := maxf(0,delta-breath) if submerged else 0.0
	breath = maxf(0,breath-delta) if submerged else minf(maximum_breath,breath+delta*maximum_breath/maxf(0.01,refill_seconds))
	if before != breath: breath_changed.emit(breath,maximum_breath)
	return empty_seconds

func can_spend(stamina_cost: float = 0, mana_cost: float = 0, flask_cost: int = 0) -> bool:
	if not is_finite(stamina_cost) or not is_finite(mana_cost): return false
	if stamina_cost < 0 or mana_cost < 0 or flask_cost < 0: return false
	return stamina >= stamina_cost and mana >= mana_cost and flasks >= flask_cost

func try_spend(stamina_cost: float = 0, mana_cost: float = 0, flask_cost: int = 0) -> bool:
	if not can_spend(stamina_cost,mana_cost,flask_cost): return false
	stamina -= stamina_cost
	mana -= mana_cost
	flasks -= flask_cost
	if stamina_cost > 0: stamina_wait = definition.stamina_delay
	if mana_cost > 0: mana_wait = definition.mana_delay
	return true

func tick(delta: float, regenerate_stamina: bool) -> void:
	stamina_wait -= delta
	mana_wait -= delta
	if stamina_wait <= 0 and regenerate_stamina:
		stamina = minf(definition.stamina_max,stamina+definition.stamina_regen*delta)
	if mana_wait <= 0: mana = minf(definition.mana_max,mana+definition.mana_regen*delta)

func heal(amount: float) -> void:
	if not is_finite(amount): return
	health = clampf(health+maxf(0,amount),0,maximum_health)
	health_changed.emit(health,maximum_health)

func apply_damage(amount: float) -> void:
	if not is_finite(amount) or amount <= 0: return
	health = maxf(0,health-amount)
	health_changed.emit(health,maximum_health)
