# 0038 — Ask about life stress before proposing a deload

- Status: accepted
- Date: 2026-11-21

## Context

An athlete deloaded two weeks earlier, had stalled lifts and an HRV a few points under their usual 40, and Today
proposed another deload. Stalls plus sustained low HRV reach the threshold of [ADR-0027](0027-deloads-with-recovery-signals.md)
and [ADR-0036](0036-deload-needs-fatigue.md), yet stress outside training can lower HRV and slow recovery without
any change in the training. The check-in already asks about unusual stress
([readiness-context-prompt](../evidence.md#readiness-context-prompt--heuristic)), but only for that day's light.
See [deload-life-stress](../evidence.md#deload-life-stress--limited).

## Decision

1. The latest yes or no answer to the stress question in the last 14 days sets `RecoveryTrend.lifeStress`:
   `reported`, `denied` or `unanswered`. "Not sure" and "skip" stay unanswered. Nothing is inferred from HRV,
   resting HR or Garmin stress.
2. When a deload would be proposed and the answer is `unanswered`, Today asks the stress question first (the
   existing check-in prompt, once per day).
3. With `reported`, the proposal keeps its score, signals and thresholds. Stress adds no points and never proposes
   on its own. The week offered changes to `DeloadPlan.stressAware`: same exercises and days, 75 % of the sets,
   about 5 % less load, RPE 8 at most. The card says why, and lists what may help (comfortable aerobic or light
   strength work, no sets to failure, sleep). A `denied` answer leaves the usual deload.
4. Accepting stores `DeloadRecord.forLifeStress = true` (optional, additive in backup format 1), so the logger
   applies the same plan and Today names the week in progress. It still counts as a recovery week.
5. Reported stress is private check-in context: it stays out of the AI context pack.

## Consequences

The athlete is asked one friendly question instead of receiving a deload that may not fit. The multipliers are
product heuristics: no trial tests what to change in training under life stress. Check-ins now load 14 days for
Today. The stress answer applies to the recommendation for 14 days, not to the readiness light, which still reads
only today's answer.
