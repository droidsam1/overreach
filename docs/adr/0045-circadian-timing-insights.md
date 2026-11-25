# 0045 — Circadian timing insights

- **Status:** Accepted
- **Date:** 2026-11-25

## Context

Zeitgebers (light, meals, exercise, sleep timing) set the body clock. The evidence review (docs/evidence.md →
Circadian timing) found: regular sleep timing predicts mortality at least as well as duration, but only
observationally; evening exercise is generally neutral for sleep unless hard exercise ends within about an hour of bed;
exercise phase shifts are small and chronotype-dependent; no trial shows that a constant training time is beneficial.
Overreach already holds sleep start/end (`DailyMetrics`) and session start times.

## Decision

`Analytics.CircadianTiming` reduces nights and sessions to circular statistics and returns at most four neutral
insights: irregular bedtime, weekend shift, variable training time, and hard sessions ending close to bedtime. Each carries
its `EvidenceReference`. It never changes load or readiness, needs ≥ 7 nights or ≥ 5 sessions, and does not
recommend a "best time of day" or clock-shifting protocol. Thresholds are labelled heuristics.

## Consequences

Users with a regular schedule see nothing. The analysis stays pure, so presentation (a Recovery card and the AI
context export) can follow without changing it. Light exposure and meal timing are not measured and stay out.

## Amendment 2026-11-25 — health lens

Overreach prioritises health over performance, so timing claims were re-checked for long-term prevention, not only
for strength or size. Only sleep regularity qualifies (docs/design/circadian-timing.md → Health lens). The hour of
exercise stays without a recommendation because cohorts disagree and trials are small; weekend-warrior patterns are
never framed as a fault; consistent training time is described as a habit and adherence observation
(`training-time-consistency` is now limited). The decision is unchanged; the criteria for a prevention-based insight
are now written down.
