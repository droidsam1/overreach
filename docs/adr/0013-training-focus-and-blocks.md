# 0013 — Training focus, balance checks and long-term blocks

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Routines, sessions and exercises can aim at different adaptations (maximal strength, hypertrophy, both, local
endurance). Progression targets, rest and programming advice should follow that focus. The product owner also
wants the app to notice when training drifts from the goal (e.g. many strength-only sessions in a row, a muscle
only ever trained in one way, a "strength" lift done at 12 reps) and to look months ahead to suggest when to
change focus.

## Decision

1. **`TrainingFocus`** (`strength`, `hypertrophy`, `mixed`, `endurance`) can be declared at three levels —
   block (profile), session and exercise (progression settings) — most specific wins. Anything not declared is
   **inferred** from the logged sets (`FocusClassifier`: reps and load relative to the estimated 1RM).
2. **Prescriptions per focus** (`FocusPrescription`): rep range, target RPE, typical %1RM, rest and default
   progression scheme, each tied to evidence (`docs/evidence.md`: `loading-by-goal`, `rest-strength`,
   `rest-hypertrophy`, `proximity-to-failure`).
3. **Goal** (`TrainingGoal`: strength, hypertrophy, general, hybrid; optional target date and priority lifts)
   in the profile. Checks and plans are always judged against it.
4. **Balance checks** (`FocusBalance`) produce findings, never automatic changes: declared vs observed focus
   (session, exercise), single-focus streaks that conflict with the goal, priority lifts without heavy work for
   a strength goal, muscles trained with a single focus when the goal needs both, low weekly volume. A declared
   block makes a matching streak intentional.
5. **Long-term view** (`BlockAdvisor`): infers past blocks from history, suggests the next focus and when to
   switch (block length, stalls, target date), and drafts a plan up to a year ahead (or to the target date,
   ending in a strength block and a taper). Strength goals get periodisation because it improves 1RM; hypertrophy
   goals are told that the model matters little and volume/effort matter more.
6. Thresholds (classification cut-offs, streak length, block lengths, templates) are labelled heuristics and
   configurable.

## Consequences

- `StrengthSession.focus`, `ProgressionSettings.focus`, `AthleteProfile.goal/declaredBlocks` are optional or
  defaulted; old data keeps decoding (tolerant `AthleteProfile` decoding).
- The UI (logger, Plan, Trends) consumes these in later PRs; the report will include findings and the plan.
