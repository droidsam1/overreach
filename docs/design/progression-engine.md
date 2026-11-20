# Progression engine

Status: implemented for v0.1 training signals (`ProgressionTargets`, `StallDetection`, `DeloadAdvisor`);
recovery signals join in v0.2 (phase 2). Evidence for every rule: `docs/evidence.md` (ADR-0012). Lives in `OverreachCore/Analytics` as pure,
deterministic functions with tests. Every output carries the reasons behind it.

## Goals

1. **Next targets:** for each exercise in today's session, propose weight × reps (and RPE) from the history and
   the exercise's progression scheme.
2. **Stall detection:** notice when an exercise stops progressing and suggest how to get moving again.
3. **Deload proposals:** recommend a deload when the whole context says so — training history in v0.1;
   plus HRV, resting HR, sleep, stress and sickness in v0.2.

## Progression schemes (per exercise, user-selectable, with a default)

| Scheme | Rule | Typical use |
| --- | --- | --- |
| Double progression (default) | Rep range, e.g. 3×8–12. When every working set hits the top of the range at RPE ≤ target, add weight (smallest increment for the equipment) and restart at the bottom. | Hypertrophy, accessories |
| Linear load | Fixed sets × reps. If all reps are completed at RPE ≤ target, add the increment next session; after 2 failures, repeat; after 3, reset −10 %. | Novice/strength main lifts |
| Rep cycle (wave) | Cycle through blocks, e.g. 12 → 8 → 5 reps, raising the load each block; restart the cycle a little heavier. | Intermediate main lifts |
| RPE-based (autoregulated) | Target reps @ RPE. Next load comes from the estimated 1RM and the RPE table (e.g. 5 @ 8 ≈ 81 % e1RM). | Advanced, fluctuating recovery |

Increments are configurable per equipment (e.g. barbell 2.5 kg, dumbbell 2 kg, machine 5 kg, microplates 1 kg).

## Signals computed from history

- Estimated 1RM per session (Epley) and its trend over 4–8 weeks.
- Performance at a matched load: reps achieved and RPE reported for the same weight over time.
- **RPE creep:** same load and reps, rising RPE across sessions → accumulated fatigue.
- Target hit/miss record per exercise (consecutive misses).
- Weekly effective sets per muscle group and this week's load against the usual week (`StrengthMetrics`,
  `Workload`).
- Weeks since the last deload.

## Stall detection

An exercise is **stalled** when, over its last 3 exposures (or 3 weeks), the e1RM has not improved by more than
~1 % *and* targets were missed at least twice. Suggestions, in order of preference, with the reason shown:

1. Microload (smaller increment) if the miss was by 1 rep.
2. Change the rep range or switch scheme (e.g. linear → double progression).
3. Add a set (if weekly volume for the muscle is below its target range) or remove one (if above).
4. Swap to a close variation for 3–4 weeks.
5. Deload the lift (−10 % for a week) — or the whole program, if several lifts stall at once (see below).

## Deload proposals

A deload week = same exercises, −50 % sets, −10 % load, RPE ≤ 7 (`DeloadPlan.standard`). Training is reduced,
not stopped: a full week off mid-programme cost some strength in the only RCT (`deload-cost`). Time since the
last deload alone never triggers one; a proposal needs a score ≥ 3, i.e. at least one performance signal.
Proposed when the score of these signals crosses a threshold (weights and thresholds configurable):

| Signal | Available from |
| --- | --- |
| Two or more main lifts stalled at the same time | v0.1 |
| RPE creep on several lifts over the last 2 weeks | v0.1 |
| Performance drop: e1RM down > 3–5 % on several lifts | v0.1 |
| Weeks since last deload ≥ planned interval (default 6) | v0.1 |
| Last week's load > 1.5× the usual week (uncoupled) | v0.1 (strength), v0.2 (with running and walking above baseline) |
| HRV 7-day trend below the personal range on ≥ 5 of the last 7 days (one HRV statistic, ADR-0024) | v0.2 |
| Resting HR ≥ 5 bpm above its baseline on ≥ 4 of the last 7 days | v0.2 |
| Short sleep (< 6 h) on ≥ 4 of the last 7 nights | v0.2 |
| Low energy (≤ 2/5) or high soreness (3/3) in ≥ 3 check-ins of the last 7 days | v0.2 |
| Sickness in a check-in of the last 7 days → return-to-training note instead of a deload | v0.2 |

Recovery signals (`deload-recovery-signals`) add 1 point each, at most 2 together, and never propose a deload on
their own: a proposal needs at least one performance signal (stalls, e1RM drop or RPE creep). Garmin stress and Body
Battery are not used (proprietary, unvalidated for this). Today shows the proposal with its reasons; accepting
records a deload week, which also resets the "weeks since the last deload" signal (ADR-0027).

For naturally cycling users, the HRV and resting-HR signals compare against phase-aware baselines, so normal
luteal shifts don't fire a deload (`docs/design/cycle-aware-training.md`, ADR-0009).

The proposal names the signals that fired, e.g. *"Deload suggested: bench and squat stalled for 3 weeks,
RPE up 1 point at the same loads, 7 weeks since the last deload."* The user accepts, postpones or dismisses it;
the choice is recorded.

## Output types (sketch)

```swift
public struct ExerciseTarget: Sendable {      // next session for one exercise
    public var sets: [PlannedSet]             // weight, reps, target RPE
    public var reasons: [ProgressionReason]
}

public enum ExerciseStatus: Sendable {         // per exercise
    case progressing, holding, stalled(suggestions: [StallSuggestion])
}

public struct DeloadProposal: Sendable {       // whole program
    public var signals: [DeloadSignal]
    public var plan: DeloadPlan                // volume and load reductions, duration
}
```
