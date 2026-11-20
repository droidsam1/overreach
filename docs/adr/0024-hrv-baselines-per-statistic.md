# 0024 — HRV baselines per statistic

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

The readiness light (ADR-0020) compares the 7-day ln HRV with the person's own 60-day range. Two sources now provide
HRV: Apple Health stores SDNN (Apple Watch), and Garmin's Personal API reports nightly RMSSD (ADR-0022). They are
different statistics with different values (`hrv-metrics`). Merging sources gives Garmin priority, so someone with
both, or who changes watch, would get a baseline that mixes the two and a false "HRV below your range" or a missed
drop.

## Decision

1. `DailyMetrics.hrvMetric` (`rmssd` / `sdnn`) labels the HRV values of a day. Apple Health aggregation sets
   `sdnn`; Garmin mapping sets `rmssd`. It is optional, so stored data stays readable (ADR-0018).
2. Merging keeps each value with its label: the statistic always comes from the source whose value is kept.
3. `ReadinessRules` judges HRV only against nights of the same statistic as the latest night. With fewer than 14 such
   nights there is no HRV signal yet, as for a new user.
4. Today's 7-day HRV average uses the same rule.

## Consequences

- Changing watch starts a new HRV baseline instead of a false alarm; the light relies on resting HR, sleep and the
  check-in meanwhile.
- Someone wearing both gets Garmin's RMSSD on nights Garmin has it and Apple's SDNN on the others. Only the latest
  night's kind is judged, so the light uses the kind they wear most.
- Values stored without a label (older cache) form their own group until they age out.
