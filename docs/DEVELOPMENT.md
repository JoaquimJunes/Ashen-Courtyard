# Development and release checks

The reproducible build targets Linux x86_64 and Godot **4.6.2 stable**. The
editor, templates and archive SHA-256 values are pinned in
[`tools/godot-toolchain.json`](../tools/godot-toolchain.json). Python 3.11 or newer
is required; the build tools use the standard library only.

## First setup

From the project directory:

```sh
python3 tools/install_toolchain.py
python3 tools/check_project.py --clean --release
```

Installation downloads approximately 1.3 GB from the official Godot releases,
verifies the archives, and extracts the editor and Linux templates into
`.artifacts/toolchain/`. It does not install anything into personal Godot settings.
Verified downloads are reused. `--templates-only` skips the editor download when
using an existing matching editor through `check_project.py --godot /path/to/godot`.

`--clean` copies the current source, including uncommitted files, to a temporary
directory without `.godot`, Git metadata, or previous build artifacts. It preserves
the working tree. The check then:

1. Rejects an engine version that does not match the lock.
2. Imports assets and scans scripts from source.
3. Runs Python tooling tests, runner self-checks, and every `tests/run*.gd` suite.
4. Exports the committed Linux preset using the release template.
5. Starts the exported executable with isolated preferences and `-- --smoke-test`,
   then runs a short headless animation benchmark to check its packaged entrypoint.
6. Packages the executable and data pack in a `.tar.gz`, preserving executable
   permissions, and writes its SHA-256 checksum.

The clean check allows 120 seconds per gameplay suite, accommodating the larger
movement matrices during parallel runs. Override with `--test-timeout SECONDS`;
timeouts still fail the check and preserve the partial log.

The smoke test uses production scenes and actions: character models, dynamically
loaded animations, movement, crouch, jump, light/heavy melee, native casting,
sword idle restoration, HUDs, and courtyard → lab →
UAL review → courtyard travel. In the UAL scene it also equips the chest fixture
and exercises all three carried-equipment layouts. Ordinary gameplay does not
enable this opt-in test mode.
It checks functionality headlessly, not visual quality or native GPU performance.

Reports and logs are under `.artifacts/ci/`; the runnable build and downloadable
archive are under `.artifacts/build/`. After extracting the archive, run
`./ashen-courtyard.x86_64` from its folder. Keep its `.pck` beside it.

## Daily checks

```sh
python3 tools/run_tests.py
python3 tools/run_tests.py --suite run_recovery_regressions --suite run_lifecycle_regressions --suite run_input_regressions
python3 tools/check_project.py
```

The runner discovers new `run*.gd` suites automatically. It isolates settings for
every suite and fails on script errors, missing summaries, timeouts, or nonzero
exits. Timeout logs retain both standard output and engine error output.
An existing editor can be selected with `--godot` or `GODOT_BIN`.

The GitHub Actions workflow runs on pushes and pull requests. It uses a fresh
checkout, pinned tools and actions, then uploads test evidence and the tested
Linux archive. It does not publish a GitHub release or deploy anything. All required
source files, generated runtime assets, and `.uid` files must be committed before
a fresh checkout can reproduce local work.

Unintegrated art libraries remain on disk but are marked `.gdignore` and excluded
from exports: the sword and starter packs, Kenney medieval kit, nature and Going
Medieval packs, and Quaternius fantasy props and village packs. This also
avoids the starter pack's documented import errors and shipping the sword whose
usage status is unresolved. Before integrating a pack, resolve its import/status
issues, remove its ignore marker and export exclusion, and run the clean checks.
Fullplate Knight, PSX Dungeon, KayKit, UAL1 and UAL2 remain imported because gameplay,
review scenes or animation tools use them. UAL2's four regular-sword clips are copied
unchanged into a shared runtime library; see [rebuild and playtest steps](UAL_SWORD_ATTACKS.md).
`tools/build_ual_action_library.gd` also extracts UAL1 sword/spell clips and the
UAL2 `UAL2_Standard_RM.glb` mantle into `native_actions.tres`, verifying the canonical
rig and every serialized key before replacing the output. See [native actions](UAL_ACTIONS.md).

The three original UAL animation GLBs stay imported for authoring tools but are
excluded from release packages. Production uses the generated lightweight rig and
verified runtime libraries. See [animation ownership, checks and benchmarking](ANIMATION_SYSTEM.md)
for adding movesets and measuring the 1/5/10/15-character workloads.
The latest [animation validation and real-GPU measurements](validation/ANIMATION_RELIABILITY.md)
record the current encounter-size limits; passing smoke tests does not establish
the 60 FPS performance target.

## Component contracts

- **Motor owns geometry.** Use `support_clearance()` and `standing_position()`
  for upright capsule placement above slopes. Step-up, mantle, dive clearance and
  ragdoll recovery share the calculation; callers retain their own collision masks
  and safety margins. Recovery must also keep its support probe within floor reach.
- **Action controller owns transitions.** Use `interrupt_for_damage()`, `die()`,
  `reset()`, `request()` and `unload()` instead of writing action state, clocks or
  queue fields from a character composition. Legacy writable aliases remain for
  compatibility and targeted fixtures; they are not the interface for new features.
- **Death precedes notification.** A lethal damage application commits `dead`
  before health/damage listeners run. Only the invocation that caused the death
  publishes `died`. Observers may apply another hit without duplicating death.
- **Cancellation is a transaction.** Ownership is released before notifications.
  Requests made inside cancellation callbacks resolve as `cancelling`; a new
  request after cancellation returns is allowed. After `unload()`, requests resolve
  as `unloaded`. Newer death/ragdoll transitions take priority over older callbacks.
- **The shared menu owns menu input.** It handles shortcuts before GUI navigation,
  gives binding capture priority, preserves dialog controls and text entry, and
  retains Escape as a fallback. HUD hosts do not forward the same event again.

Tests for new mechanics should include relevant interruption, reset, death and
scene-unload sequences, not just successful execution. Dispatch actual input
events when testing GUI interaction. Geometry and physics tests should cover the
supported 30/60/120 Hz rates and run through the prescribed regression runner.

After source or architecture changes, refresh the context graph using the project
builder described in [`GRAPHIFY_GUIDE.md`](../GRAPHIFY_GUIDE.md).

Character assets follow the [UAL foundation](UAL_FOUNDATION.md) and
[Blender workflow](BLENDER_CHARACTER_WORKFLOW.md). Keep `.blend` source under
ignored `art_source/`; exported GLBs and runtime resources are the reproducible
game inputs. No Blender installation is required in CI.

## Boundaries

The build currently targets Linux only. Visual playtesting and native release
profiling remain separate checks. Existing procedural-world, gameplay-save and
content milestones remain in the development roadmap.

Swimming source clips are extracted by `tools/build_ual_swim_library.gd` into
`assets/animations/ual/anim_ual_native_swimming_library_v01.tres`, with the same native-key verification.
The release smoke test also covers the production swimming station and water exit.
