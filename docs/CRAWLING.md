# Crawling

The shared UAL player uses the approved Mixamo `Crawling.fbx` hands-and-knees
motion. Hold the remappable crouch control (default **C**) for **0.5 seconds**.
Standing first becomes crouching; a short press from crouching rises on release.
Once crawling, release keeps the stance. Tap to return to crouch if clear, then
tap again to stand. A blocked request is discarded; it never expands into a roof.

Camera-relative WASD travels at **1 m/s**, including sideways and reverse input.
Facing follows the camera only when the motor's rotation checks allow it. Crawl
has no stamina cost and permits the existing delayed regeneration. Movement waits
for the short entry pose blend before advancing. Equipment is stowed and lock-on,
combat, spells, healing, gadgets, sprint, jump, dodge and ledge acquisition are
disabled until a deliberate exit. Rejected actions spend nothing and are not buffered.

## Clearance and ownership

The supported passage is **0.90 m**, including separate floor/ceiling variations
reducing local clearance to **0.88 m**. The original preview's head peaked near
0.83 m; the shoulder-fitted pose remains inside the supported passage. The earlier
0.60 m belly-crawl proposal was superseded by this animation
and the confirmed 0.90 m target. This is not a lower belly-crawl mode.

- `features/crawling/crawling.gd` owns persistent stance; the shared action
  lifecycle validates entry/exit. `CharacterIntent.crouch_held` supports scripts
  and physical controls through the same timed input path.
- `features/crawling/crawling.tres` stores the 0.5 s hold, 1 m/s speed, 0.25 s
  blend, 2 cm step limit and prone capsule dimensions.
- `CharacterMotor` alone changes collision or moves the body. The prone capsule
  has a 0.43 m radius, 1.9 m total length and a horizontal local axis. Full-volume
  posture samples bound travel to 2.5 cm; translation uses shape sweeps. Folding
  keeps the lower surface supported and does not require artificial extra headroom.
  Solver collision margins stay enabled. Turns that overlap solids retain the
  previous facing, leaving translation and retreat available.
- `crawl_presentation.gd` samples the retargeted clip through the existing physics
  pose driver. Fitted damage hitboxes and mouth-based breath capture the completed
  pose. Rendering cannot advance the animation; walking foot placement is disabled.
  Idle holds the current crawl pose because this source has no separate idle clip.

Gravity, falling damage and grounded hurt recovery remain shared. Deep water
releases crawling into swimming. A mouth submerged in shallow water consumes
breath even when the player is still crawling. A living, settled ragdoll can
recover to a validated crawl location on a flat floor when standing is blocked;
otherwise it retains physical recovery. There is no dedicated prone get-up clip,
so this fallback starts in the safe crawl pose instead of playing a standing rise.
Death keeps the existing encounter behavior. Pause cancels incomplete device
holds; teleport, reset and unload clear posture and playback state.

The crawl asset is fitted to the UAL player. Model profiles without that clip
reject entry with `missing_animation`; they retain existing locomotion support.

## Assets and rebuilding

The downloaded FBX is unchanged. `art_source/mixamo/anim_ual_crawl_retarget_reviewed_v01.glb` is the
approved mannequin retarget from the interactive preview, baked at 30 Hz over
1.8 seconds. See its sibling `README.md` for provenance and fitting details.
It is an authoring snapshot, not a native UAL source clip. The game loads only
`assets/animations/ual/anim_ual_mixamo_crawling_library_v01.tres`, with all 195 bone transform tracks
and the source hashes. The mannequin mesh, skeleton and UAL source clips are unchanged.

Rebuild the runtime library with `python3 tools/build_mixamo_crawl.py`.
The baked `attached_shoulders_v1` fitting keeps both shoulder sockets connected
to the rigid chest. It leans the torso forward by 23 degrees and solves the arm
rotations to retain the source wrist positions and palm orientations. No limb
lengths or joint translations change; the other source tracks and both original
files are preserved. See `tools/crawl_retarget.py` and the authoring README.
This does not re-run the FBX retarget or add runtime inverse kinematics.
No Blender installation or preview file is required to build the game.

## Playtest and checks

Run the project, open **Test Grounds → Crouching**, and use the marked **CRAWL
0.90 m** lane between the existing upright crouch tunnels. It contains a 2 cm
floor variation and a separate 2 cm ceiling dip. The neighboring **0.80 m** lane
should block safely. Enable the existing capsule and fitted hitbox diagnostics
to inspect posture and sensing.

Acceptance: hold C → crawl → cross the 0.90 m lane → stop → reverse through it →
attempt to rise under the roof → exit → tap to crouch → tap to stand. Repeat on
both shoulders, then enter the swimming pool and verify breath and restoration.

Focused suites: `run_crawling`, `run_crawl_lifecycle`, `run_crouch`,
`run_tunnel_clearance`, `run_swimming_alignment`, `run_pose_clock`.
Run them through `tools/run_tests.py --suite NAME`; vary `--render-fps 30/120`
independently of their 30/60/120 Hz physics matrices. The full runner discovers
both crawling suites automatically. `tools/check_project.py --clean --release`
also checks packaged crawl playback and return to ordinary locomotion.
