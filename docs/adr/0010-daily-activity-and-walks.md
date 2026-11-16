# 0010 — Daily steps and walks: low-weight load, recovery tool and lifestyle constraint

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Steps are already read into `DailyMetrics.steps` but nothing uses them. Many users walk a lot outside
training (commute, a dog that needs several walks a day). That activity can help or hurt recovery, and the
user may want advice on it ("take a longer walk today", "a short easy jog with the dog fits today").

What the evidence supports:

- **Walking as active recovery helps a little.** Dupuy et al. (2018, 99 studies): active recovery produced a
  small-to-moderate reduction in DOMS and perceived fatigue versus passive rest. It is cheap and safe, so it
  is a reasonable default on easy and red days.
- **Low-intensity walking is not "cardio interference".** Interference grows with the frequency and duration
  of *endurance training* (Wilson et al. 2012), and recent meta-analyses find that even concurrent aerobic
  training does not compromise hypertrophy or maximal strength, only explosive strength (Schumann et al.
  2022). Walking sits well below that intensity.
- **Too little daily movement blunts the benefits of exercise.** Short-term step reduction to ≈ 5,000/day
  impaired the metabolic response to an exercise bout, while ≈ 8,500/day protected it (Burton et al.,
  *Med Sci Sports Exerc* 2021;53:333–340). Very low-step days are worth flagging.
- **Unusual volume is still load.** A long or hilly walk far above the user's habit adds lower-limb load,
  mostly relevant around heavy leg days and long runs. There is no good evidence for a fixed step "cost";
  it has to be judged against the person's own baseline.
- **Many short walks vs few long ones:** no evidence of a difference for training recovery. Breaking up
  sitting time has metabolic benefits, but we will not claim a recovery effect we cannot back.

## Decision

1. Daily activity is modelled separately from training: total steps, and **walks** as bouts (from Health
   walking workouts, Garmin walking activities, or ≥ 10 min of continuous steps in Health's step samples).
2. Personal baseline: 28-day median steps and walking minutes. Only *deviations* from the baseline count as
   extra load; habitual walking is part of the user's normal state and is not penalised.
3. Load: walking above baseline adds a small lower-limb load (HR-based TRIMP when available, otherwise a
   conservative minutes-based estimate) to the acute:chronic ratio and to leg fatigue. Weight is
   configurable and starts low.
4. Recommendations use walks as a tool, always with the reason:
   - Red day or day after a hard leg session / long run: easy walk 20–40 min suggested as active recovery.
   - Very low steps for several days: nudge to move more (no fixed goal; relative to baseline).
   - Day before a heavy leg session or a key run, and legs already fatigued: keep walks easy and flat, avoid a
     big spike over baseline.
   - Green day, legs fresh, no hard run in the next 24–48 h: an optional short easy run (e.g. with the dog)
     can be suggested if the user enabled it.
5. **Lifestyle constraints win.** The profile can mark walks as fixed ("I walk a dog, ~N walks a day",
   minimum walks, whether running with the dog is possible). Recommendations never remove a fixed walk;
   they only adjust length, pace or route (flat vs hills), or suggest splitting/merging when the user says
   either is fine.
6. No recommendation about walk *distribution* claims a recovery benefit; it is offered only as a lifestyle
   choice.

## Consequences

- No dog-specific logic in the engine: "dog" is a profile flag that enables wording and the "run with the
  dog" option. Users without a dog get the same walking logic.
- Phase placement and details: `docs/design/daily-activity.md`.

## References

- Dupuy O et al. *Front Physiol* 2018;9:403. doi:10.3389/fphys.2018.00403
- Wilson JM et al. *J Strength Cond Res* 2012;26(8):2293–2307
- Schumann M et al. *Sports Med* 2022;52:601–612. doi:10.1007/s40279-021-01587-7
- Burton HM et al. *Med Sci Sports Exerc* 2021;53(2):333–340
