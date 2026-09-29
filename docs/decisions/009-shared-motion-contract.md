# ADR 009 — Resolve character motion through a shared contract

Status: implemented, 20 September 2026.

## Context

Side/back rolls could lose forward motion during a fall after the analogous
forward dive had been fixed. Independent executors mixed ground travel limits,
animation clocks and airborne velocity. The player loop's zero-velocity default
made missing requests destructive. Sharing a low-level motor alone did not
prevent contradictory requests. The Warden also used a separate motion loop.

## Decision

Use typed `MotionRequest` values and per-character `MotionResolver` state inside
a shared `CharacterSimulation` action/motion/contact step. Existing knight and
Warden compositions call that step. Actions submit horizontal requests; the
motor remains the only character-body mover.

Declare inherit, retained-departure or directed air motion in shared ability
definitions. Missing motion means inherit airborne momentum. Intentional braking
is explicit. A per-action `MotionBudget` caps ground travel and consumes requests
against walls, while exhaustion never implicitly stops falling motion.

Contact comes from the motor/coordinator, not animation progress. Executors keep
their phase clocks. Contact replacements start at zero elapsed action time.
Finish/cancel/reset/handover clear temporary ownership, with named signal handlers
that do not keep RefCounted component graphs alive after unload.

AI target loss is idle intent, not a reason to stop gravity. Explicit encounter
freeze/death remains separate. The Warden retains its ground handling and does
not automatically acquire the knight's landing damage or ragdoll rules.

## Consequences

Future actions and NPCs reuse the tested motion policy boundary instead of
copying dodge-specific falling branches. Shared policies are verified through
real collisions in both a minimal character fixture and the production Warden
at 30/60/120 Hz. Existing player suites preserve the reviewed gameplay.

Outer input/resource/presentation orchestration and distinct action executors
remain; this is an incremental extraction, not a universal character framework.
New traversal modes and enemy landing policies still require design and tests.
See [the implementation walkthrough](../MOTION_PIPELINE.md).
