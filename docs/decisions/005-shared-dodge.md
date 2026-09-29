# 005 — Shared directional dodge; remove the legacy hop

**Status:** implemented at the user's request, 20 September 2026.

## Problem

World setup chose different default dodge definitions. The laboratory used the
adaptive forward dive; the courtyard retained the earlier hop and a different
stationary-dodge direction. Shared character code alone did not guarantee
consistent behavior while hosts could select different movement profiles.

## Decision

Remove the legacy hop definition and executor, its player/session selection flag,
unused timing aliases, comparison UI and unused lab-specific adapter. The shared
ability controller selects the forward dive for forward/stationary intent and
the grounded reference rolls for side/back intent. Levels provide environment,
combat context and reset rules, not movement variants.

Keep focused read-only Resources for forward and grounded rolls. Each action owns
its timers and selected launch plan. Actions request motion, the motor owns body
movement, and presentation follows gameplay state. This change does not retune
the existing dive or side/back rolls, and introduces no new movement mechanic.

## Validation and consequence

Compare actual player traces in courtyard, laboratory and preview at 30/60/120 Hz,
using identical calibration geometry to isolate scene configuration. Retain
actual-level collision, gap, reset, combat, input, camera and pose checks.
Retire tests that specifically required the removed hop; retain useful contact,
pose and lifecycle checks against current actions.

The higher old arc is no longer available. The current shallow dive does not
clear the 3 m lane from the tested 0.45 m setback; it falls and resets. The
requested 0.5/0.6 m raised-platform crossings retain their existing acceptance
checks. Do not silently increase dive height to reproduce the retired arc.

## Review boundary

The user explicitly requested: **ask before developing anything further**.
Complete this removal and validation, then stop. Present the proposed next change
and ask before additional development, tuning, refactoring or advancing to jumping.
