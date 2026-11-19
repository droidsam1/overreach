# ADR-0019: Training plans are declared blocks that rotate through routines

- Status: accepted
- Date: 2026-11-19

## Context

Issue #34 asks to train from a plan an AI drafted, for example "a year in three blocks: hypertrophy, strength
and hybrid". The `overreach.plan` v1 import (ADR-0017) already brings routines and per-exercise settings. Two
things were missing:
- the same exercise needs different sets and reps in different blocks (5 × 3 in strength, 3 × 8–12 in hypertrophy),
  but progression settings are per exercise;
- the app did not know which session comes next.

Plans also go stale. People miss days, get sick and move sessions around. A calendar of dated sessions breaks on
the first missed day.

## Decision

1. **A plan is a list of declared blocks** (`AthleteProfile.declaredBlocks`, ADR-0013). `TrainingBlock` gains an
   optional `name` and `routineIDs`, the routines it rotates through. Blocks were already declared there for the
   focus checks, so a planned block also makes a matching streak intentional. No new store or backup section.
2. **Prescriptions belong to the routine.** `Routine.prescriptions` maps an exercise of the routine to a
   `ProgressionScheme`. A session started from that routine uses it instead of the exercise's own settings. A
   strength block and a hypertrophy block use different routines. Prescriptions hold sets, reps and target RPE,
   never loads: the progression engine still sets the load from recent sessions, as #34 decided.
3. **Next session = rotation, not dates.** The running block is the last declared block that started on or
   before today and has not ended. Its next routine follows the routine of the last session started from the block.
   `StrengthSession.routineID` records that routine. A missed day moves the plan back instead of skipping a session.
   Free sessions do not move it. This rule is `PlanSchedule` (Analytics). It is pure and makes no evidence claim:
   it only follows the order the user, or their AI, wrote.
4. **The format grows without a new version.** `overreach.plan` v1 gains the optional `routines[].prescriptions`,
   `blocks` and `startDate` (ADR-0017: adding optional fields keeps the version). Importing blocks keeps declared
   blocks that start before the plan and replaces the rest. The context pack shows blocks with their routines and
   routines with their prescriptions, so an AI can revise a plan. A routine `id` from the pack updates that routine.
5. **Stored data stays readable** (ADR-0018). Every new field is optional or decoded with a default, so the frozen
   v1 backup still loads.

## Consequences

- Train shows "Up next in your plan" with the block and week, and starts it in one tap.
- Editing a routine keeps its prescriptions. The editor does not change them yet, so an AI or a new import does.
- Not covered yet (#34 follow-up): comparing planned with completed work, deload weeks inside a block, and
  proposing adjustments after missed sessions or poor recovery.
