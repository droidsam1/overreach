# 0027 — Deload proposals on Today, reinforced by recovery

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

`DeloadAdvisor` proposed deloads from training signals only (stalls, e1RM drops, RPE creep, weeks since the last
deload, load spikes), and no screen showed the proposal. Phase 2 adds recovery data (HRV, resting HR, sleep,
check-ins). The evidence is that no recovery marker identifies accumulated fatigue on its own: overtraining is a
diagnosis of exclusion, resting HRV and HR barely change in functional overreaching, and HRV can even rise
(`deload-recovery-signals`).

## Decision

1. `RecoveryTrend` (Analytics) judges each of the last 7 days with the readiness rules (same baselines; one HRV
   statistic, ADR-0024) and counts sustained signals: HRV trend below range on ≥ 5 days, resting HR up on ≥ 4,
   < 6 h sleep on ≥ 4 nights, low energy or high soreness in ≥ 3 check-ins, and any sick check-in.
2. Each sustained recovery signal adds 1 point, at most 2 together. A proposal still needs a score ≥ 3 and at least
   one performance signal, so recovery alone never proposes a deload. A recent sick check-in gives no proposal:
   the readiness light and the plan review already say to rest and return gradually (`illness-return`).
3. Garmin stress and Body Battery are not used (proprietary, unvalidated for this).
4. Today shows the proposal with each reason and its evidence level, and the plan (`DeloadPlan.standard`).
   **Start deload week** records a `DeloadRecord` in the profile (optional field, ADR-0018); it marks the week on
   Today and resets "weeks since the last deload". **Not now** hides the proposal for a week
   (`deloadPostponedUntil`), after which it returns if the signals persist.
5. While a deload week covers today, the workout logger reduces each exercise's target with the plan and says so.

## Consequences

- Deloads stay rare and explainable; a bad week of sleep alone does not interrupt progress.
- During the deload week the logger applies the plan to every target (`DeloadPlan.applied`): half the working sets
  (at least one), about 10 % less load rounded to the exercise's increment, RPE 7 at most, with the reason shown.
  Progression resumes from the lighter sessions afterwards ("then build back up").
- Phase-aware baselines for naturally cycling users (ADR-0009) are not applied yet.
