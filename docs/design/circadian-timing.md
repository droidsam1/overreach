# Circadian timing: sleep and training clock times

Why and how Overreach looks at *when* the athlete sleeps and trains. Decision: [ADR-0045](../adr/0045-circadian-timing-insights.md).
Evidence entries: [Circadian timing](../evidence.md#circadian-timing). Reviewed 2026-11-25.

## The idea

Zeitgebers ("time givers") are cues that keep the body's clocks aligned: light (dominant), sleep and wake times, meals
and exercise. The question was whether Overreach should help the athlete keep these steady, and whether the time of
day of training matters for recovery.

## What the evidence supports

| Claim | Verdict | Evidence key |
| --- | --- | --- |
| Regular sleep timing matters at least as much as duration for mortality | Supported, observational | `sleep-regularity` (limited) |
| Weekend-vs-weekday sleep shift ("social jetlag") harms health | Small associations only | `social-jetlag` (limited) |
| Hard evening exercise delays sleep | Only when it ends about 1 h before bed or later; ≥ 2 h before is neutral or helpful | `evening-exercise-sleep` (moderate) |
| Exercise shifts the body clock (morning earlier, late evening later) | Real but small, chronotype-dependent, conflicting for early evening | `exercise-circadian-phase` (moderate, no rule) |
| Training at the same time every day improves recovery | Not shown. A steady time goes with *more exercise* (observational) | `training-time-consistency` (limited) |
| One time of day gives better strength or size gains | No: no evidence for or against | `training-time-consistency` |
| The hour of exercise changes long-term disease risk (heart, diabetes) | Cohorts disagree (afternoon, evening or morning); small trials mixed; any time lowers risk | `exercise-timing-prevention` (limited, no rule) |
| Concentrating activity in 1–2 days is worse for health | No: still lower mortality and CVD risk than inactivity | `weekend-warrior` (limited) |
| Late main meal hampers weight loss | One programme study; meals are not measured | `meal-timing` (limited, no rule) |
| Morning light is the strongest human clock cue | Supported (AHA scientific statement); Overreach has no light data | advice only |

The initial intuition that hard exercise 4–5 h before bed delays sleep is **not** supported. Neither is the idea that
a constant training time is more important than the effect of exercise itself on health; the benefits of exercise do
not depend on the hour.

## Guidelines for the app

1. Describe, do not prescribe a time. Never rank morning against evening training.
2. Show insights only with ≥ 7 nights of sleep timing or ≥ 5 sessions; a regular schedule shows no warning.
3. One neutral sentence per insight with its evidence level; no diagnosis, no causal claim (observational data).
4. Warn about evening training only when hard sessions end within 60 min of the usual bedtime in ≥ 25 % of cases.
   The suggestion is to finish ≥ 2 h earlier or make that session easier.
5. Never change load, readiness or the plan from timing insights. Sleep *duration* keeps its own rule (`readiness-sleep`).
6. Treat free days (waking Sat/Sun) as a proxy for the work schedule and say so; shift workers will be misread.
7. Light and meal timing are not measured: they may appear as optional advice, never as a score.

## Health lens (2026-11-25 review)

Overreach is about health first, so a recommendation may rest on long-term prevention even when it changes nothing in
performance. A null result for strength or size therefore does not close the question. The review applied this test
to each timing claim; a prevention claim may drive an insight only when it passes all of these:

1. The direction agrees across independent designs, ideally including a randomised trial or a pooled analysis.
2. It is not explained by chronotype, shift work, job, season or reverse causation (these are what confound
   accelerometer cohorts of exercise timing).
3. The action it implies is cheap, safe and reversible for the athlete.

Result: only **sleep regularity** passes enough to show a neutral observation (large cohorts in two countries,
consistent direction, duration-independent for all-cause mortality, safe action). **Exercise hour for prevention** fails
(1) and (2): UK Biobank cohorts favour afternoon, evening or morning depending on the population, and trials in type 2
diabetes are small and mixed. So no preferred hour is recommended, and the app says that total moderate-to-vigorous
activity at any time is what the evidence supports. Revisit when a trial or pooled analysis agrees. **Weekend-warrior**
patterns still lower risk, so uneven weeks are never framed as a health fault. **Meal timing** has too little evidence
and is not measured.

Where it does change behaviour: the regularity insight is health advice, independent of training and of the load or
readiness rules, and is worded as prevention ("regular sleep and wake times go with lower long-term risk"), not as a
performance tip.

## What is built

`Analytics.CircadianTiming` (pure): circular mean and spread of bedtime, wake time and training start; weekend
midpoint shift; hard sessions ending within the buffer before bed. Insights: `irregularBedtime`, `socialJetlag`,
`variableTrainingTime`, `hardSessionsNearBed`. Thresholds (labelled heuristics) live in `CircadianTiming.Settings`:
60 min bedtime spread, 60 min weekend shift, 2 h training spread, 60 min buffer, 25 % share.

## Continue from here

- [#347](https://github.com/droidsam1/overreach/issues/347) — Recovery card with real data and localized texts.
- [#348](https://github.com/droidsam1/overreach/issues/348) — AI context export.
- [#349](https://github.com/droidsam1/overreach/issues/349) — Validate the thresholds on real histories.
- [#351](https://github.com/droidsam1/overreach/issues/351) — Regularity from sleep midpoint and wake time (health lens).
