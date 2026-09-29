extends Node3D
## Instance-local visual/audio lifetime, separate from damage and targeting.
const SAMPLE_RATE := 22050
const MAX_PREPARED_TONES := 32
const MAX_TONE_SECONDS := 2.0
var prepared_tones: Dictionary = {}

func clear() -> void:
	for child in get_children():
		if child is AudioStreamPlayer: child.stop()
		child.queue_free()

func effect(pos: Vector3, color: Color, radius: float) -> void:
	var mesh := Shapes.orb(self,0.15,Vector3.ZERO,color)
	mesh.top_level = true
	mesh.global_position = pos
	var mat := mesh.material_override as StandardMaterial3D
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween := create_tween().bind_node(mesh).set_parallel(true)
	tween.tween_property(mesh,"scale",Vector3.ONE*radius/0.15,0.28)
	tween.tween_property(mat,"albedo_color:a",0.0,0.28)
	tween.chain().tween_callback(mesh.queue_free)

func prepare_tone(frequency: float, duration: float) -> AudioStreamWAV:
	# Prepare during scene/loadout setup. Playback never synthesizes missing cues.
	if not is_finite(frequency) or frequency <= 0 or frequency > SAMPLE_RATE*0.5 or not is_finite(duration) or duration < 1.0/SAMPLE_RATE or duration > MAX_TONE_SECONDS: return null
	var key := [frequency,duration]
	if prepared_tones.has(key): return prepared_tones[key]
	if prepared_tones.size() >= MAX_PREPARED_TONES: return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	var bytes := PackedByteArray()
	var count := int(duration*SAMPLE_RATE)
	bytes.resize(count*2)
	for i in count:
		var sample := sin(TAU*frequency*i/float(SAMPLE_RATE))*0.16*(1.0-float(i)/count)
		bytes.encode_s16(i*2,int(sample*32767))
	stream.data = bytes
	prepared_tones[key] = stream
	return stream

func create_tone_player(frequency: float, duration: float) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = prepared_tones.get([frequency,duration])
	if stream == null: return null
	var audio := AudioStreamPlayer.new()
	add_child(audio)
	audio.stream = stream
	audio.finished.connect(audio.queue_free)
	return audio

func tone(frequency: float, duration: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var audio := create_tone_player(frequency,duration)
	if audio == null: return
	audio.play()
