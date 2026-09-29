extends SceneTree
## Native, uncapped wall-clock benchmark. Does not alter saved scenes or preferences.
const WARMUP_SECONDS := 4.0
const SAMPLE_SECONDS := 15.0
var actor: CharacterBody3D
var cases: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()
func _process(delta: float) -> bool:
 if is_instance_valid(actor): actor.yaw += delta*0.4
 return false
func milliseconds() -> float: return Time.get_ticks_usec()/1000.0
func stats(values: Array[float]) -> Dictionary:
 values.sort()
 var total := 0.0
 for value in values: total += value
 return {"p50":values[int((values.size()-1)*0.50)],"p95":values[int((values.size()-1)*0.95)],"p99":values[int((values.size()-1)*0.99)],"max":values.back(),"mean":total/values.size()}
func rss_kib() -> int:
 var file := FileAccess.open("/proc/self/status",FileAccess.READ)
 if file == null: return 0
 while not file.eof_reached():
  var line := file.get_line()
  if line.begins_with("VmRSS:"):
   return int(line.trim_prefix("VmRSS:").strip_edges().split(" ",false)[0])
 return 0
func run() -> void:
 if DisplayServer.get_name() == "headless":
  printerr("Benchmark requires native rendering; do not use --headless or --fixed-fps.")
  quit(1)
  return
 Engine.max_fps = 0
 Engine.physics_ticks_per_second = 60
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 CameraPreferences.loaded = true
 CameraPreferences.reset()
 CameraPreferences.set_value("distance",6.0)
 for count in [0,4]:
  actor = null
  var started := milliseconds()
  change_scene_to_file("res://scenes/movement_lab.tscn")
  await process_frame
  await process_frame
  var lab: Node3D = current_scene
  lab.go_to_station(0)
  actor = lab.player
  actor.controller.manual = true
  actor.max_health = 100000.0
  actor.health = actor.max_health
  actor.pitch = -0.24
  var scene_ms := milliseconds()-started
  started = milliseconds()
  for i in count:
   var warden: CharacterBody3D = load("res://scenes/boss.tscn").instantiate()
   warden.services = lab.services
   var angle: float = TAU*i/maxi(1,count)
   warden.position = actor.position+Vector3(cos(angle)*4.0,0,sin(angle)*4.0)
   lab.add_child(warden)
   warden.target = actor
  var population_ms := milliseconds()-started
  # Defaults: PS1 effects on, diagnostics closed, all original lab fixtures present.
  PSXStyle.enabled = true
  RenderingServer.global_shader_parameter_set("psx_enabled",true)
  var warmup_end := milliseconds()+WARMUP_SECONDS*1000
  while milliseconds() < warmup_end: await process_frame
  var frames: Array[float] = []
  var process_ms: Array[float] = []
  var physics_ms: Array[float] = []
  var max_draw_calls := 0.0
  var max_primitives := 0.0
  var max_active_bodies := 0.0
  var max_nodes := 0.0
  var static_peak := 0.0
  var rss_peak := rss_kib()
  var next_memory := milliseconds()+1000
  var sample_start := milliseconds()
  var previous := sample_start
  while milliseconds()-sample_start < SAMPLE_SECONDS*1000:
   await process_frame
   var now := milliseconds()
   frames.append(now-previous)
   previous = now
   process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
   physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
   max_draw_calls = maxf(max_draw_calls,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
   max_primitives = maxf(max_primitives,Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
   max_active_bodies = maxf(max_active_bodies,Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
   max_nodes = maxf(max_nodes,Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
   static_peak = maxf(static_peak,Performance.get_monitor(Performance.MEMORY_STATIC))
   if now >= next_memory:
    rss_peak = maxi(rss_peak,rss_kib())
    next_memory = now+1000
  var durations := stats(frames)
  var result := {"case":"lab_baseline" if count == 0 else "lab_four_wardens","additional_wardens":count,"sample_seconds":(previous-sample_start)/1000,"frames":frames.size(),"mean_fps":1000.0/durations.mean,"frame_ms":durations,"process_ms":stats(process_ms),"physics_ms":stats(physics_ms),"peak_draw_calls":max_draw_calls,"peak_rendered_primitives":max_primitives,"peak_active_physics_bodies":max_active_bodies,"peak_nodes":max_nodes,"peak_static_memory_mib":static_peak/(1024*1024),"sampled_peak_rss_mib":rss_peak/1024.0,"scene_ready_ms":scene_ms,"population_ms":population_ms}
  cases.append(result)
  print("BENCHMARK CASE: ",JSON.stringify(result))
 var report := {"engine":Engine.get_version_info().string,"debug_build":OS.is_debug_build(),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"resolution":[root.size.x,root.size.y],"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"physics_hz":Engine.physics_ticks_per_second,"warmup_seconds":WARMUP_SECONDS,"conditions":"Standalone Compatibility, PS1 on, diagnostics off, camera orbit 0.4 rad/s. Four normal AI wardens attack a stationary knight with extra instance health. Native wall-clock intervals; no fixed-fps. Memory RSS sampled each second. Engine process/physics monitors are periodically refreshed values, not per-frame CPU profiles. Scene-ready timings are warm-cache in-process, not cold startup. No release templates installed.","cases":cases}
 var path := "res://.artifacts/performance/lab-benchmark.json"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
 var file := FileAccess.open(path,FileAccess.WRITE)
 if file == null:
  printerr("Cannot write benchmark report")
  quit(1)
  return
 file.store_string(JSON.stringify(report,"  ")+"\n")
 print("BENCHMARK REPORT: ",ProjectSettings.globalize_path(path))
 quit()
