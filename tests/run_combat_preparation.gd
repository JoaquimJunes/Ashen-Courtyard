extends SceneTree
## Prepared combat resources are shared; active sounds/projectiles remain world-owned.
const Effects = preload("res://features/presentation/world_effects.gd")
const Services = preload("res://features/combat/combat_services.gd")
const Aim = preload("res://features/combat/aim_request.gd")
const Strike = preload("res://features/combat/strike_token.gd")
const Bolt = preload("res://features/abilities/data/bolt.tres")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func settle() -> void:
	await process_frame
	await process_frame

func original_wave(frequency: float, duration: float) -> PackedByteArray:
	# Preserve the pre-cache synthesizer as a byte-for-byte behavior oracle.
	var bytes := PackedByteArray()
	var count := int(duration*22050)
	bytes.resize(count*2)
	for i in count:
		var sample := sin(TAU*frequency*i/22050.0)*0.16*(1.0-float(i)/count)
		bytes.encode_s16(i*2,int(sample*32767))
	return bytes

func synthesis() -> void:
	var effects := Effects.new()
	root.add_child(effects)
	for cue in [[600.0,0.18],[340.0,0.18],[180.0,0.12],[270.0,0.12],[360.0,0.12],[110.0,0.12],[250.0,0.07]]:
		var stream := effects.prepare_tone(cue[0],cue[1])
		check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo,"Cue preparation preserves audio format")
		check(stream != null and stream.data == original_wave(cue[0],cue[1]),"Prepared cue matches original wave bytes: "+str(cue))
		check(effects.prepare_tone(cue[0],cue[1]) == stream,"Repeated preparation reuses the exact stream")
	var count := effects.prepared_tones.size()
	for cue in [[NAN,0.18],[INF,0.18],[-1.0,0.18],[0.0,0.18],[22050.0,0.18],[600.0,NAN],[600.0,INF],[600.0,-1.0],[600.0,0.0],[600.0,1e-8],[600.0,100.0]]:
		check(effects.prepare_tone(cue[0],cue[1]) == null,"Invalid or oversized cue is rejected")
	check(effects.prepared_tones.size() == count,"Rejected preparation leaves ready cues untouched")
	check(effects.create_tone_player(999.0,0.12) == null and effects.prepared_tones.size() == count,"Playback never synthesizes an unprepared cue")
	var first := effects.create_tone_player(600.0,0.18)
	var second := effects.create_tone_player(600.0,0.18)
	check(first != second and first.stream == second.stream,"Overlapping sounds share only their immutable stream")
	first.finished.emit()
	await settle()
	check(not is_instance_valid(first) and is_instance_valid(second),"Finishing one sound does not remove another instance")
	effects.effect(Vector3.ZERO,Color.RED,0.5)
	effects.effect(Vector3.ONE,Color.BLUE,0.8)
	var visuals: Array[MeshInstance3D] = []
	for child in effects.get_children():
		if child is MeshInstance3D: visuals.append(child)
	check(visuals.size() == 2 and visuals[0].material_override != visuals[1].material_override,"Overlapping effects retain independent instances and fading materials")
	var saved: AudioStream = second.stream
	effects.clear()
	await settle()
	check(not is_instance_valid(second) and not is_instance_valid(visuals[0]) and not is_instance_valid(visuals[1]),"Clear cancels all active cue and effect nodes")
	check(effects.get_child_count() == 0 and effects.prepare_tone(600.0,0.18) == saved,"Clear retains prepared streams for the next action")
	var remaining := Effects.MAX_PREPARED_TONES-effects.prepared_tones.size()
	for index in remaining: check(effects.prepare_tone(1000.0+index,0.01) != null,"Explicit preparation fills remaining bounded capacity")
	check(effects.prepare_tone(2000.0,0.01) == null and effects.prepared_tones.size() == Effects.MAX_PREPARED_TONES,"Arbitrary cue requests cannot grow the cache indefinitely")
	check(effects.prepare_tone(600.0,0.18) == saved,"A full cache still reuses existing prepared cues")
	effects.free()

func world_lifetime() -> void:
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var services := Services.new()
	services.host = host
	# Standalone scene assembly prepares Warden cues before deferred context entry.
	check(services.prepare_tone(180.0,0.12) != null,"A pending world context accepts cue preparation before ready")
	host.add_child(services)
	check(services.projectile_scene != null and services.projectile_scene.resource_path == "res://scenes/projectile.tscn","Scene preparation retains the projectile PackedScene")
	for frequency in [600.0,340.0]:
		check(services.effects.prepared_tones.has([frequency,0.18]),"Default spell cue is prepared before casting")
	var prepared: AudioStreamWAV = services.prepare_tone(600.0,0.18)
	var caster := Combatant.new()
	caster.services = services
	host.add_child(caster)
	caster.setup(100,preload("res://features/character/data/knight_body.tres"))
	# Replacing the prepared fixture proves casting instantiates the held resource.
	var original: PackedScene = services.projectile_scene
	var prototype := original.instantiate()
	prototype.set_meta("prepared_fixture",true)
	var retained := PackedScene.new()
	check(retained.pack(prototype) == OK,"Prepared projectile fixture packs")
	prototype.free()
	services.projectile_scene = retained
	services.cast(caster,Bolt,Aim.new(Vector3(0,2,0),Vector3(0,2,-20)),Strike.new())
	services.cast(caster,Bolt,Aim.new(Vector3(1,2,0),Vector3(1,2,-20)),Strike.new())
	var first: Node = services.transients[0]
	var second: Node = services.transients[1]
	check(first != second and first.get_meta("prepared_fixture",false) and second.get_meta("prepared_fixture",false),"Repeated casts instantiate the retained resource without replacing it")
	check(first.get_parent() == host and second.get_parent() == host,"Prepared projectile instances retain independent world ownership")
	var audio: AudioStreamPlayer = services.effects.create_tone_player(600.0,0.18)
	services.clear()
	await settle()
	check(not is_instance_valid(first) and not is_instance_valid(second) and not is_instance_valid(audio),"World reset removes active projectiles and sounds")
	check(services.projectile_scene == retained and services.prepare_tone(600.0,0.18) == prepared,"World reset retains prepared projectile and audio resources")
	var cue_count: int = services.effects.prepared_tones.size()
	services.tone(600.0,0.18)
	check(services.effects.get_child_count() == 0 and services.effects.prepared_tones.size() == cue_count,"Headless playback stays skipped without synthesis")
	var boss = load("res://scenes/boss.tscn").instantiate()
	boss.services = services
	boss.controller.manual = true
	host.add_child(boss)
	boss.set_physics_process(false)
	for definition in [boss.tuning.combat.boss_combo,boss.tuning.combat.boss_overhead,boss.tuning.combat.boss_lunge]:
		var frequency: float = boss.presentation.cue_frequency(definition)
		check(services.effects.prepared_tones.has([frequency,0.12]),"Warden config prepares the tone derived from its attack definition")
	var old_effects: Node = services.effects
	var active: AudioStreamPlayer = services.effects.create_tone_player(600.0,0.18)
	host.queue_free()
	await settle()
	check(not is_instance_valid(services) and not is_instance_valid(old_effects) and not is_instance_valid(active),"Scene unload releases world services and all active cues")
	var next_host := Node3D.new()
	root.add_child(next_host)
	current_scene = next_host
	var next_services := Services.new()
	next_services.host = next_host
	next_host.add_child(next_services)
	check(next_services.projectile_scene != null and next_services.effects.prepared_tones.size() == 2,"The next scene prepares a fresh world resource owner")
	check(next_services.prepare_tone(600.0,0.18) != prepared,"Audio resource ownership does not leak between scenes")
	next_host.queue_free()
	await settle()

func arena_cues() -> void:
	var arena = load("res://scenes/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	arena.player.set_physics_process(false)
	arena.boss.set_physics_process(false)
	for cue in [[110.0,0.12],[250.0,0.07]]:
		var stream: AudioStreamWAV = arena.services.effects.prepared_tones.get(cue)
		check(stream != null,"Arena damage cue is prepared during setup: "+str(cue))
		check(stream != null and stream.data == original_wave(cue[0],cue[1]),"Arena damage cue preserves its original waveform")
	var prepared_count: int = arena.services.effects.prepared_tones.size()
	arena.player.damaged.emit()
	arena.boss.damaged.emit()
	check(arena.services.effects.prepared_tones.size() == prepared_count,"Damage callbacks need no additional cue synthesis")
	arena.queue_free()
	await settle()

func run() -> void:
	await synthesis()
	await world_lifetime()
	await arena_cues()
	print("COMBAT PREPARATION RESULT: %s checks, %s failures" % [checks,failures])
	quit(1 if failures else 0)
