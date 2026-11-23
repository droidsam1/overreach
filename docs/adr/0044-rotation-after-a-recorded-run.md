# 0044 — Adapt the rest of the rotation after a recorded run

- **Status:** Proposed
- **Date:** 2026-11-23

## Context

A hybrid athlete rotates strength sessions A, B, C, D (ADR-0033). A has heavy squats, B heavy deadlifts, C and D load
the legs less. After A on Sunday, an unplanned easy run on the Monday rest day leaves B for Tuesday. Athletes often
answer this by resting another day and pushing B to Wednesday, without knowing whether the evidence asks for it.

Overreach already holds a run back after leg work (`concurrent-lower-body-run`), but not the reverse: a run that is
already recorded never changes the next strength session. The data is there: the run's duration, HR, training effect,
elevation and pain report (ADR-0043), the check-in's soreness, readiness, and each rotation slot's leg demand
(`RotationProjection.Demand`). Only recorded data can be used; a run that may happen later is unknown.

Evidence reviewed on 2026-11-23 (`run-before-strength-carryover`, `rotation-reorder-after-run` in `docs/evidence.md`):

- **Chronic.** Concurrent training does not blunt hypertrophy or maximal strength on average (Schumann et al. 2022);
  interference grows with endurance frequency and duration (Wilson et al. 2012) and may be larger for running than
  cycling at the fibre level (Lundberg et al. 2022). One extra easy run a week is a small dose.
- **Acute.** Aerobic work before strength reduces strength moderately, most after > 30 min or moderate-to-high
  intensity, little after short easy work (Markov et al. 2022). Leg-press volume was lower 4 and 8 h after aerobic
  work but back at 24 h, for intervals and continuous work alike (Sporer and Wenger 2003). Unaccustomed or downhill
  running damages muscle: knee-extensor strength took about 48 h to recover in lab studies, and the repeated-bout effect
  makes regular runners less affected. Heavy leg strength work leaves residual fatigue for one to several days (Doma
  et al. 2017).
- **Reordering.** With weekly volume equated, how many days a muscle is trained and therefore how sessions are spread
  across the week matters little (`frequency-volume-equated`). Letting athletes choose the day's session by readiness
  gave equal or better leg strength than a fixed order (McNamara and Stearne 2010, small trial), and autoregulated
  loads match or beat fixed loads for maximal strength (Zhang et al. 2021).
- **HRV.** HRV-guided strength programming has not beaten fixed programming in trials (Bittencourt et al. 2024; small,
  older women); it stays context, not the trigger.

No trial tests "swap B and C after an extra run". The ladder below is a heuristic built on these findings.

## Decision

1. **Carry-over of a recorded run (`RunCarryover`, Analytics).** *Notable* when the run was hard (training effect,
   tag), long (> 60 min or > 110 % of the longest of 30 days), hilly, unaccustomed (no run in 14 days), ended less than
   24 h before the next lift, or followed by soreness or pain that holds. *Light* otherwise; *unknown* without
   duration. Thresholds are configurable heuristics.
2. **Only a leg-heavy next session is reconsidered.** An upper-body or light slot needs nothing.
3. **Decision ladder (`RotationAdjustment.suggest`).** Red readiness, illness and symptoms keep their own rules first.
   Then: light carry-over and green readiness → **keep** (strength is back after 24 h of easy aerobic work). Notable
   carry-over, amber readiness, or a heavy leg session ≤ 48 h before the run → **swap** the heavy slot with the next
   lighter one when every slot stays in the cycle and the heavy slot keeps ≥ 48 h to the following heavy-leg session;
   else **postpone one day** when the cycle absorbs it; else **keep capped** (no load increase, top sets at RPE 8, not
   counted for stalls). Swapping comes before postponing because it keeps weekly frequency and volume.
4. **Accepted adjustments are recorded.** A swap or postponement is stored (`RotationAdjustment`, optional backup
   field) and rotation detection tolerates it, so Today keeps the projection. Manual per-day choices stay unstored
   (ADR-0033).
5. **Suggest, never apply.** Today shows one secondary line with Accept / Keep plan and a "why" that names the run,
   the hours since, the previous leg session, readiness and the evidence level.

## Consequences

- The athlete's habit of postponing becomes a choice with reasons; after an easy run the usual answer is keep.
- A swap changes the order inside one cycle only; the original order resumes after the pair.
- Adjustments live in `AthleteProfile.rotationAdjustments` (device and backup; absent in older backups). A swap is
  matched by the two workouts on the day it was planned; a postponement by the days it moved the session.
- Apple Health runs lack training effect: intensity counts as unknown and the explanation says so.
- Descent is a better eccentric marker than gain; until #274 the rule uses gain.
- Proposed until replay on real histories (#273) checks how often each outcome fires and whether adjusted sessions
  performed better. Tasks: umbrella #268, #269–#274.
