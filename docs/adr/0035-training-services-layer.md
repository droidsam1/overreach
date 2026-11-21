# 0035 — One application layer gathers training data and composes rules

- **Status:** Proposed
- **Date:** 2026-11-21

## Context

`Domain` holds the entities and the source protocols; `Analytics` holds pure rules. Between them and the screens
there is no layer of its own: each presentation model reads the sources, chooses its own date window and failure
handling, then combines several rules. The same question gets different answers on different screens:

- Today said the last deload was 51 weeks ago while Plan said 2 weeks: `DeloadAdvice` and `PlanAnalysis` read
  different deload dates and read runs with different failure rules.
- Runs are read in five places (Today, Plan, History, Assistant, the deload advice) with three different rules for
  unavailable and failing sources.
- The Assistant sends one metrics row per source and day; Today merges them, Garmin first.
- Whether a deload week is in progress is decided in `DeloadAdvice`, `WorkoutModel` and `PlanAnalysis`.
- Stalls are computed in `WorkoutModel`, `PlanAnalysis`, `DeloadAdvisor` and `ContextPackBuilder`, with different
  progression-settings fallbacks.

[Inventory and tasks](../design/training-services.md).

## Decision

1. A new pure-Swift module, `TrainingServices` (OverreachCore), is the application layer. It depends on `Domain`
   and `Analytics`, and is tested on Linux.
2. It owns **reading**: one reader per kind of data (metrics merged per day in source priority, runs deduplicated,
   watch strength recordings, sessions) with one rule for unavailable and failing sources, and returns the data with
   its provenance and failures.
3. It owns **answers to domain questions** used by more than one screen, each in one type: the athlete's recovery
   status (last recovery, deload in progress, breaks to confirm), the status of each lift (stalled or not, settings
   in use), readiness for a day, and the deload recommendation.
4. Presentation models and `AIExchange` ask `TrainingServices` and only turn answers into screen state and text.
   They read repositories directly only to edit what the screen edits (a session, a routine, the profile).
5. `Analytics` stays a library of pure rules with no I/O; `TrainingServices` decides which rules apply and with
   which inputs.
6. A check fails when a presentation module calls a source's `runs(from:to:)` or `dailyMetrics(in:)`, or one of
   the rules that `TrainingServices` wraps.

## Consequences

- One question, one answer: Today, Plan, Workout, History and the AI context cannot disagree by construction.
- The reading rules (windows, source priority, failures) are tested once.
- Presentation models get thinner, and their tests use a fake `TrainingServices` instead of building sources.
- One more module and a migration across five presentation modules. Each service is added only when two consumers
  share the question (ADR-0014 warns against abstraction for its own sake).
