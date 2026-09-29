# Initial Test Grounds performance baseline

Measured 22 September 2026 with Godot 4.6.2, Compatibility, Intel Iris Xe and
1280 × 720 native rendering. **Standalone debug build**, not the editor viewport;
release export templates are not installed. VSync and the frame cap were disabled.
PS1 effects were enabled; diagnostics were closed.

Each case had 4 seconds of warm-up and 15 seconds of wall-clock frame samples.
The camera orbits at 0.4 rad/s. The busy case adds four normal AI wardens attacking
a stationary knight with extra per-instance health. All ordinary lab fixtures
remain. This is a controlled moderate stress case, not final open-world content.

| Measurement | Normal lab | Lab + four wardens |
|---|---:|---:|
| Average FPS | 154.1 | 134.2 |
| Frame interval p50 (ms) | 6.35 | 7.11 |
| Frame interval p95 (ms) | 8.95 | 10.62 |
| Frame interval p99 (ms) | 10.20 | 11.62 |
| Frame interval max (ms) | 44.26 | 22.25 |
| Peak draw calls | 864.0 | 1081.0 |
| Peak active physics bodies | 1.0 | 5.0 |
| Sampled peak process RSS (MiB) | 269.4 | 275.0 |
| Peak Godot static allocations (MiB) | 58.4 | 59.5 |
| Scene-ready time (ms) | 551.6 | 504.8 |
| Warden creation time (ms) | 0.0 | 18.9 |

The busy case's p99 fits the 16.7 ms target, but maximum frame intervals in both
cases exceed it. This is evidence of headroom in this scene, not a guarantee of
stutter-free 60 FPS or future world density. The normal lab's isolated maximum
was higher than the busy case; one short run cannot attribute that outlier.
A first pass gave similar average rates (155 / 133 FPS).

RSS is sampled once per second and is distinct from Godot's tracked allocations;
GPU memory is not separately measured. Scene-ready timings include scene creation
inside an already-running engine, not complete cold startup. Engine process and
physics monitors in the raw report refresh periodically and must not be treated
as per-frame CPU profiles. The next profiling target is occasional long frames;
release measurements remain required before setting content limits.

## Reproduce

Run without `--headless` or `--fixed-fps`, and leave the game window focused:

```sh
"<USER_HOME>/Desktop/Ashen Courtyard/Godot_v4.6.2-stable_linux.x86_64" --path <PROJECT_ROOT> --resolution 1280x720 --script res://tools/benchmark_lab.gd
```

The temporary stress population exists only in the benchmark process. The script
writes `.artifacts/performance/lab-benchmark.json`; it does not modify saved scenes
or camera/keybinding preferences. Close other demanding applications for comparisons.

## UI optimization verification

`tests/run_ui_optimizations.gd` verifies that 100 unchanged path updates cause no
extra mesh rebuild, equal replacement snapshots reuse geometry, endpoint and
parent-transform changes rebuild correctly, and hidden/reopened paths stay valid.
It also checks saved Settings-tab restoration and malformed-data fallback.
Together with menu, keybinding and camera regressions: **232 checks passed**.
