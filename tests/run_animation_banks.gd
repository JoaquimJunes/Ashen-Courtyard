extends SceneTree
## Regression: validation is atomic and distinct movesets never collide by alias.
const Profile = preload("res://features/presentation/animation_profile.gd")
const Catalog = preload("res://features/items/item_catalog.gd")
const Base = preload("res://features/presentation/data/ual_animation_profile.tres")
const DATA = preload("res://features/items/data/catalog.tres")
const Driver = preload("res://tests/action_test_driver.gd")
var checks := 0
var failures := 0
var world: Node3D
var actor: CharacterBody3D
var other: CharacterBody3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func action_profile(source_index: int = 1, count: int = 1) -> Resource:
	var profile := Profile.new()
	profile.scope = Profile.Scope.ACTIONS
	profile.rig_contract = Base.rig_contract
	profile.native_combat = AnimationLibrary.new()
	for index in count:
		var definition: Resource = Base.light_attacks[(source_index+index)%2].duplicate()
		var role := "attack_%s" % index
		var recovery := "recovery_%s" % index
		profile.native_combat.add_animation(role,Base.clip_for(definition.clip))
		profile.native_combat.add_animation(recovery,Base.clip_for(definition.recovery_clip))
		# First alias deliberately collides with the character's default A clip.
		definition.clip = &"combat/sword_regular_a" if index == 0 else StringName("custom/attack_%s" % index)
		definition.recovery_clip = StringName("custom/recovery_%s" % index)
		profile.aliases[String(definition.clip)] = role
		profile.aliases[String(definition.recovery_clip)] = recovery
		profile.light_attacks.append(definition)
	return profile

func item_with_profile(id: StringName, profile: Resource) -> Resource:
	var item: Resource = DATA.find(&"practice_blade").duplicate()
	item.id = id
	item.display_name = String(id)
	item.actions = item.actions.duplicate()
	item.actions.actions = item.actions.actions.duplicate()
	item.actions.actions[0] = item.actions.actions[0].duplicate()
	item.actions.actions[0].presentation = item.actions.actions[0].presentation.duplicate()
	item.actions.actions[0].presentation.animations = profile
	return item

func validation() -> void:
	var player: AnimationPlayer = actor.model.animation
	var before := player.get_animation_list()
	var original := player.get_animation(&"k_idle")
	var invalid: Resource = Base.duplicate()
	invalid.aliases = invalid.aliases.duplicate()
	invalid.aliases.erase("k_idle")
	check(not invalid.install(player,actor.model.rig),"Partial character profile is rejected")
	invalid = Base.duplicate()
	invalid.aliases = invalid.aliases.duplicate()
	invalid.aliases["bad/alias/nested"] = "idle"
	check(not invalid.install(player,actor.model.rig),"Malformed aliases reject before installation")
	invalid = Base.duplicate()
	invalid.rig_identifier = &"different_rig"
	check(not invalid.install(player,actor.model.rig),"Wrong rig identifier rejects")
	invalid = action_profile()
	check(not invalid.install(player,actor.model.rig),"Action-only bank cannot replace locomotion")
	for kind in ["missing_bone","method","nan_key","nan_timing","nan_blend","ambiguous"]:
		invalid = action_profile()
		var clip: Animation = invalid.clip_for(&"combat/sword_regular_a").duplicate()
		invalid.native_combat.remove_animation(&"attack_0")
		invalid.native_combat.add_animation(&"attack_0",clip)
		match kind:
			"missing_bone": clip.track_set_path(0,NodePath("Armature/Skeleton3D:not_a_bone"))
			"method":
				var track := clip.add_track(Animation.TYPE_METHOD)
				clip.track_set_path(track,NodePath("."))
			"nan_key": clip.track_set_key_value(0,0,Vector3(NAN,0,0))
			"nan_timing": invalid.light_attacks[0].strike_start = NAN
			"nan_blend": invalid.light_attacks[0].blend_in = NAN
			"ambiguous":
				invalid.native_actions = AnimationLibrary.new()
				invalid.native_actions.add_animation(&"attack_0",clip)
		check(not invalid.validate(player,actor.model.rig),"Reject invalid bank: "+kind)
		if kind == "nan_timing": check("light_attacks[0].strike_start" in invalid.last_error,"Timing error identifies the exact attack and field")
		if kind == "nan_blend": check("light_attacks[0].blend_in" in invalid.last_error,"Blend error identifies the exact attack and field")
	check(player.get_animation_list() == before and player.get_animation(&"k_idle") == original,"Rejected profiles preserve the complete working bank")
	var skeleton := Skeleton3D.new()
	for index in actor.model.skeleton.get_bone_count():
		skeleton.add_bone(actor.model.skeleton.get_bone_name(index))
		skeleton.set_bone_parent(index,actor.model.skeleton.get_bone_parent(index))
		skeleton.set_bone_rest(index,actor.model.skeleton.get_bone_rest(index))
	check(Base.rig_contract.valid(skeleton),"Reference rig contract accepts identical names, parents and rests")
	var parent := skeleton.get_bone_parent(1)
	skeleton.set_bone_parent(1,-1)
	check(not Base.rig_contract.valid(skeleton),"Reference rig contract rejects a changed hierarchy")
	skeleton.set_bone_parent(1,parent)
	var rest := skeleton.get_bone_rest(1)
	rest.origin.x += 0.01
	skeleton.set_bone_rest(1,rest)
	check(not Base.rig_contract.valid(skeleton),"Reference rig contract rejects a changed rest transform")
	skeleton.free()
	var spell: Resource = Base.spell_cast.duplicate()
	spell.blend_out = NAN
	check(not spell.valid(Base),"Nonfinite spell blending rejects")
	check(spell.last_error.begins_with("blend_out:"),"Spell validation names the invalid field")

func runtime() -> void:
	var catalog := Catalog.new()
	catalog.definitions.assign(DATA.definitions)
	var first: Resource = action_profile(1,3)
	var second: Resource = action_profile(0)
	catalog.definitions.append(item_with_profile(&"three_attacks",first))
	catalog.definitions.append(item_with_profile(&"other_moveset",second))
	check(catalog.build(),"Two custom banks validate independently despite shared alias")
	for character in [actor,other]:
		character.items.catalog = catalog
		character.items.inventory.catalog = catalog
	var owned: StringName = actor.items.inventory.grant(&"three_attacks")[0]
	var replacement: StringName = actor.items.inventory.grant(&"other_moveset")[0]
	var other_owned: StringName = other.items.inventory.grant(&"other_moveset")[0]
	var rejected_record: Dictionary = actor.items.to_record()
	var original_record: Dictionary = actor.items.to_record()
	var original_libraries: PackedStringArray = actor.model.animation.get_animation_list()
	rejected_record.equipment.primary = String(owned)
	rejected_record.legacy_flask = "missing_owned_flask"
	check(not actor.items.restore(rejected_record) and actor.items.to_record() == original_record,"Invalid restore preserves inventory and equipment")
	check(actor.model.animation.get_animation_list() == original_libraries and actor.items.resolver.animation_bank.get_binding(first) == null,"Invalid restore cannot install a partially prepared animation bank")
	check(actor.items.equipment.assign(&"primary",owned) and other.items.equipment.assign(&"primary",other_owned),"Equipping prepares custom banks before combat")
	var bank: RefCounted = actor.items.resolver.animation_bank
	var prepared: RefCounted = bank.get_binding(first)
	check(prepared != null and prepared.resolved(&"combat/sword_regular_a") != &"combat/sword_regular_a","Custom aliases resolve in a private bank")
	check(prepared.clip_for(&"combat/sword_regular_a") == Base.clip_for(Base.light_attacks[1].clip),"Resolved custom A alias retains requested B source")
	var library_count: int = actor.model.animation.get_animation_library_list().size()
	var other_pose: Array = other.presentation.capture_pose()
	var other_clock: float = other.model.animation.current_animation_position
	for expected in [0,1,2,0]:
		actor.stamina = 100
		check(await Driver.start(actor,&"light"),"Custom light starts")
		check(actor.combo == expected,"Arbitrary moveset visits combo index "+str(expected))
		var captured: RefCounted = actor.actions.active_item.animations
		check(captured == prepared,"Accepted action captures the prepared binding")
		actor.actions.timer = actor.actions.active_definition.windup
		actor.presentation.sword_attack.sample(0)
		var definition: Resource = first.light_attacks[expected]
		check(actor.model.animation.assigned_animation == prepared.resolved(definition.clip) and actor.model.animation.get_animation(actor.model.animation.assigned_animation) == first.clip_for(definition.clip),"Action samples its exact custom source clip")
		check(not actor.items.equipment.assign(&"primary",replacement),"Active action prevents moveset replacement")
		actor.actions.timer = actor.actions.active_definition.windup+actor.actions.active_definition.active_seconds+actor.actions.active_definition.recovery
		actor.actions.advance(0)
		actor.actions.finish_if_idle()
	check(actor.model.animation.get_animation_library_list().size() == library_count,"Action starts do not load or install animation banks")
	check(other.presentation.capture_pose() == other_pose and other.model.animation.current_animation_position == other_clock,"A second character retains independent pose and clock")
	check(actor.items.equipment.assign(&"primary",replacement),"Completed action permits another prepared moveset")
	actor.stamina = 100
	check(await Driver.start(actor,&"light") and actor.combo == 0,"Changing movesets resets the combo inside its grace window")
	actor.actions.cancel(&"test")
	# Invalid equipment must not replace the working item or partially install clips.
	var bad: Resource = action_profile()
	bad.rig_identifier = &"wrong_rig"
	bad.rig_contract = Base.rig_contract.duplicate()
	bad.rig_contract.rig_identifier = &"wrong_rig"
	catalog.definitions.append(item_with_profile(&"bad_rig",bad))
	check(catalog.build(),"Catalog can describe equipment for another rig")
	var invalid_owned: StringName = actor.items.inventory.grant(&"bad_rig")[0]
	var before: PackedStringArray = actor.model.animation.get_animation_list()
	check(not actor.items.equipment.assign(&"primary",invalid_owned) and actor.items.equipment.primary == replacement and actor.model.animation.get_animation_list() == before,"Wrong-rig equipment leaves loadout and libraries unchanged")

func custom_spell() -> void:
	var profile := Profile.new()
	profile.scope = Profile.Scope.ACTIONS
	profile.rig_contract = Base.rig_contract
	profile.native_actions = AnimationLibrary.new()
	profile.spell_cast = Base.spell_cast.duplicate()
	# Deliberately remap existing aliases to different source poses.
	var aliases := [profile.spell_cast.enter_clip,profile.spell_cast.idle_clip,profile.spell_cast.shoot_clip,profile.spell_cast.exit_clip]
	for index in aliases.size():
		var source: Animation = Base.clip_for(aliases[(index+1)%aliases.size()])
		var role := StringName("spell_%s" % index)
		profile.native_actions.add_animation(role,source)
		profile.aliases[String(aliases[index])] = role
	var catalog: Resource = actor.items.catalog
	var item: Resource = DATA.find(&"azure_bolt").duplicate()
	item.id = &"custom_spell"
	item.actions = item.actions.duplicate()
	item.actions.actions = item.actions.actions.duplicate()
	item.actions.actions[0] = item.actions.actions[0].duplicate()
	item.actions.actions[0].presentation = item.actions.actions[0].presentation.duplicate()
	item.actions.actions[0].presentation.animations = profile
	catalog.definitions.append(item)
	check(catalog.build(),"Custom spell profile validates")
	var id: StringName = actor.items.inventory.grant(item.id)[0]
	check(actor.items.equipment.assign(&"spell",id,0),"Equipping prepares spell animations")
	actor.selected_spell = 0
	check(await Driver.start(actor,&"cast"),"Custom spell starts without loading")
	var captured: RefCounted = actor.actions.active_item.animations
	var action: Resource = actor.actions.active_definition
	actor.selected_spell = 1
	for point in [action.windup*0.2,action.windup*0.85,action.windup,action.windup+action.recovery*0.8]:
		actor.actions.timer = point
		actor.presentation.spell.sample(0)
		var sampled: Dictionary = profile.spell_cast.sample_time(point,action,captured)
		check(actor.model.animation.assigned_animation == captured.resolved(sampled.clip) and actor.model.animation.get_animation(actor.model.animation.assigned_animation) == captured.clip_for(sampled.clip),"Spell phases use captured custom clip identities after selection changes")
	actor.actions.cancel(&"test")
	var default_spell: StringName = actor.items.inventory.grant(&"azure_bolt")[0]
	check(actor.items.equipment.assign(&"spell",default_spell,0),"Default spell can replace a finished custom spell")
	check(actor.items.resolver.animation_bank.get_binding(profile) == null and not actor.model.animation.has_animation_library(captured.library_name),"Unequipped banks release instance libraries")
	actor.reset_for_lab(Transform3D.IDENTITY)
	check(actor.items.resolver.animation_bank.bindings.size() == 1,"Retry retains only the default character bank")

func heavy_return_handoff() -> void:
	for reason in [&"heavy_charge_released",&"heavy_charge_damage"]:
		for alpha in [0.0,0.7]:
			actor.reset_for_lab(Transform3D.IDENTITY)
			check(await Driver.start(actor,&"heavy"),"Heavy return handoff fixture starts")
			actor.actions.timer = 0.02
			actor.model.update_pose(0)
			actor.pose_driver.previous.capture(actor.model.skeleton)
			actor.actions.timer = actor.actions.active_definition.windup*0.4
			actor.model.update_pose(0)
			actor.pose_driver.current.capture(actor.model.skeleton)
			actor.pose_driver.current_transform = actor.model.transform
			var authoritative: Array = actor.presentation.capture_pose()
			actor.pose_driver.display(alpha)
			check(actor.presentation.capture_pose() != authoritative,"Fixture displays a different interpolated heavy pose")
			actor.actions.cancel(reason)
			check(actor.presentation.sword_attack.return_pose == authoritative,"Heavy cancellation captures physics pose for %s at render weight %s" % [reason,alpha])
			check(actor.model.transform == actor.pose_driver.current_transform,"Heavy cancellation restores the authoritative model frame")
	actor.reset_for_lab(Transform3D.IDENTITY)

func run() -> void:
	GameInput.configure()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	Shapes.solid(world,Vector3(40,1,40),Vector3(0,-0.5,0),Color.GRAY)
	var session := root.get_node("GameSession")
	actor = session.create_player(world,session.configure_world(world),true)
	other = session.create_player(world,session.configure_world(world),true)
	for pair in [[actor,0],[other,5]]:
		pair[0].controller.manual = true
		pair[0].reset_for_lab(Transform3D(Basis.IDENTITY,Vector3(pair[1],0,0)))
	for frame in 4:
		await physics_frame
		await process_frame
	for character in [actor,other]:
		character.set_physics_process(false)
		character.model.set_process(false)
	validation()
	await runtime()
	await custom_spell()
	await heavy_return_handoff()
	var retained_bank: RefCounted = actor.items.resolver.animation_bank
	world.free()
	check(retained_bank.player == null and retained_bank.bindings.is_empty(),"Scene exit releases animation bank ownership")
	print("ANIMATION BANKS: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
