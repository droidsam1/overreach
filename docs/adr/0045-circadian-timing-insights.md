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
