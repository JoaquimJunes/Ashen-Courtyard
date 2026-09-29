# Swimming, diving, and water exits

Implemented for playtesting in **Esc → Test Grounds → Swimming (05)**. The shared
player uses this mechanic in any scene containing a `WaterVolume`; the laboratory
only supplies water and obstacles. The normal UAL player is the animation target.

## Controls and acceptance route

- WASD swims relative to the camera. At the surface movement stays level;
  underwater it follows camera pitch as well as yaw.
- Walking into water starts swimming at **1.3 m** of immersion. Press **C**
  while at least **1.0 m** deep to start swimming earlier; shallower water keeps
  the ordinary crouch toggle. Floating retains the existing waterline and 0.9 m
  shore exit threshold.
- Hold the crouch binding (**C** by default) to dive/descend. Hold the jump binding
  (**Space**) to ascend. Releasing movement holds depth after a short deceleration.
- Hold the sprint binding (**Shift**) to swim faster. After exhaustion, release
  Shift to rearm fast swimming; normal swimming lets stamina recover.
- Swim toward a safe ledge to grab and pull up. Once attached, the existing hang,
  sideways movement, forward pull-up, and dodge-to-release controls apply.
- Attacks, spells, healing, lock-on and dodges are unavailable while swimming.
  Weapons are temporarily stowed and return to the equipped layout on exit.

Playtest **enter → float → swim fast → dive → stop at depth → resurface → climb
out**. Check strokes, waterline alignment, control response and the transition to
the existing UAL pull-up. The pool has 0.4 / 1.2 / 4.5 m sections, stairs, a shallow
ramp, a raised exit, a blocked exit and a submerged obstruction. The water no
longer resets the player. Reset/station switching still restores the character.

## Rules and tuning

`features/swimming/swimming.tres` uses the editable `swim_definition.gd` defaults:

| Setting | Initial value |
| --- | --- |
| Normal / fast swimming | 2.5 / 4 m/s |
| Fast-swim stamina cost | 20 per second |
| Breath / full refill | 20 / 3 seconds |
| Drowning | 10% maximum health per second after breath expires |
| Automatic / crouch entry depth | 1.3 / 1.0 m |
| Safe falling-entry depth | 2 m |
| Maximum exit above surface | 0.5 m |
| Pull-up cost | Existing mantle cost, initially 10 stamina |

Normal swimming and floating permit the existing stamina regeneration/delay.
Breath follows the visible mouth/nose marker on the fitted head, including crouch,
ragdoll and ledge poses. Entry/exit use 2 cm surface hysteresis and travelled-segment
time accounting. Floating animation keeps that marker above water. Drowning
continues with laboratory combat disabled and does not repeatedly stagger the
player. Ordinary water hits use hurt recovery without the descending-hit ragdoll.
A living ragdoll can recover into sufficiently deep water when its capsule fits.
Death uses the existing host death/reset flow; physical corpse buoyancy is absent.

Deep-water crossings cancel incompatible actions, fall damage and dive-roll
landing. Shallow floor contacts retain ordinary landing consequences. A blocked
or unaffordable water exit leaves the player swimming. Low roofs cannot force a
standing collider into solid geometry.

## Components and ownership

- `WaterVolume` is a reusable Area3D scene. Its origin is the centre of the water
  surface; `size` defines X/Z extent and depth below it. Author stationary,
  horizontal, unscaled volumes. The optional translucent surface is presentation.
  Water queries stay within the observer's physics world; segment intersection
  detects fast entries even when the final position has reached the pool floor.
- The per-player swimming component owns immersion, surface/depth transitions,
  exertion intent and entry/exit policy. Resources own breath and publish
  `breath_changed`. Damage uses the existing damage/death transaction.
- `HeadWaterDetector` samples the completed head pose independently of movement
  mode and camera tint. See [fitted hitboxes and breathing](HITBOXES.md) for profile
  authoring, the debug overlay and precise damage-query ownership.
- `CharacterIntent` adds 3D swim direction and a vertical axis. Rebound jump/crouch
  keys supply held depth input without queuing their land actions.
- `MotionRequest.WATER` carries full 3D velocity, capsule height and a complete
  character-local capsule transform through
  `CharacterSimulation`. The motor remains the sole collision-body mover. It
  disables gravity, ground snapping and stair stepping in water, checks capsule
  translation/rotation/expansion, and safely restores the standing shape at shore or mantle.
- The coordinator keeps `surface_swimming` and `underwater_swimming` separate
  from committed actions. Water transitions resolve before landing notifications.
- Ledge acquisition adds a water-origin candidate; it reuses the existing hand,
  clearance, attachment, mantle, shimmy and release machinery without the land
  jump-height requirement. Candidate validation includes the landing destination
  and available pull-up stamina.
- Swimming presentation uses UAL1 `Swim_Idle_Loop` / `Swim_Fwd_Loop`. Submerging
  and entry blend existing poses; there is no dedicated new headfirst dive clip.
  UAL2 `ClimbUp_1m` remains the native pull-up source. Neither animation moves the
  collision body. Walking foot placement is disabled while swimming.
- Water presentation advances once per physics tick before movement. Its completed
  torso/head pose supplies the capsule axis and center, including horizontal
  offsets, pitch and entry/idle blends. The motor sweeps the requested transform
  and limits posture rotation/translation per tick. Presentation maps onto the
  transform actually accepted, retaining a compatible prone body beneath a roof.
  A blocked transition can swim away and resume without a deferred rotation snap.
  Hitboxes and breath sample this accepted pose before `simulation_stepped`; render
  updates do not advance it again. Land and ragdoll keep their existing clocks.
- Neutral native upright/prone origins are editable in `SwimDefinition`. Only
  surface swimming adjusts the shared frame to keep the mouth above water. Diving
  carries that offset into a torso-pivoted pitch, allowing the visible head to move
  naturally underwater. Exit, mantle, teleport and reset clear the override.
- The breath HUD warns below 25%. Its tint follows **camera** immersion,
  independently of the player's breath sample. Input labels respect rebinding.

Rebuild the native library with the pinned Godot executable and
`--headless --path . --script tools/build_ual_swim_library.gd`. The builder uses the
existing native-clip verification helpers and checks every serialized key before
replacing `assets/animations/ual/anim_ual_native_swimming_library_v01.tres`. Original GLBs are unchanged.

## Validation

The `run_swimming*` suites exercise real collision, input, UAL playback, breath,
interruptions, reset/unload and the production pool. Movement, entry, resource and
ledge cases cover 30/60/120 Hz. The native animation suite checks source fidelity,
finite poses, head alignment, equipment restoration and independent camera tint.
The packaged smoke route includes entry, submerging, resurfacing and a ledge exit.
`run_swimming_alignment` additionally checks full-body snapshots, mouth position,
blocked upright transitions and escape at 30/60/120 Hz. Use runner `--render-fps 24`
and `--render-fps 144` to vary rendering independently of those physics rates;
repeated render calls must leave the swimming animation clock and pose unchanged.

Run `python3 tools/run_tests.py` for regressions and
`python3 tools/check_project.py --clean --release` for clean imports, all suites,
Linux export and packaged smoke validation. Native visual inspection checks poses;
headless passing tests alone are not a substitute for Neth's hands-on review.

Currents, moving/wavy water surfaces, underwater combat, physical corpse buoyancy,
free climbing, and native UAL swimming retargeting for the legacy knight are outside
this pass. The legacy appearance uses a torso-pivoted fallback with the same shared
posture, collider and sensing clock; its clearance and land behavior are tested.
