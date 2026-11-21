# 0036 — Require fatigue for a deload proposal

- **Status:** Accepted
- **Date:** 2026-11-21

## Context

Several stalled lifts and six elapsed weeks reached the deload threshold even when the athlete recovered well
and the same sets felt steady. A lift removed from the training rotation could still contribute within 28 days.
Bell et al.'s Delphi consensus describes deloading as reducing training stress to manage fatigue. Trials of
scheduled reductions or breaks do not validate a trigger for individual athletes. See
[deload-design](../evidence.md#deload-design--limited) and [stall-heuristics](../evidence.md#stall-heuristics--heuristic).

## Decision

Keep the score threshold and require a lift signal plus a fatigue signal. A performance drop or RPE creep
satisfies both requirements. A load spike or sustained recovery signal supplies fatigue when stalled lifts supply
the lift signal. The interval contributes only to the score. Keep the existing recovery cap and grace period.

Lift signals need an eligible exposure within 28 days. Restrict them to exercises in active planned or dated
routines, a repeated rotation, or the most recent known routine, in that order. Use the latest template for
a known routine and the latest session for a rotation slot without a template. Use recency alone when no
current structure is available.

## Consequences

Today can name the lifts contributing to a whole-programme deload. The stall assessment exposes its flat
window, last exposure, best estimated 1RM with the working set behind it, and per-lift suggestions.
The thresholds and the choice of current exercises remain product heuristics.
