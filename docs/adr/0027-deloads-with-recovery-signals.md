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

## Consequences

- Deloads stay rare and explainable; a bad week of sleep alone does not interrupt progress.
- Workout targets do not yet apply the deload reductions automatically during the deload week; Today states the
  plan (next step).
- Phase-aware baselines for naturally cycling users (ADR-0009) are not applied yet.
