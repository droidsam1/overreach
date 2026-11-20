# 0025 — HRV: one series per metric, never a mixed baseline

- **Status:** Proposed
- **Date:** 2026-11-20

## Context

Apple Watch writes HRV to Health as SDNN from spot readings. Garmin's Personal API gives the whole-night average
RMSSD (ADR-0022). [ADR-0024](0024-hrv-baselines-per-statistic.md) labels the retained daily value with its statistic
and limits the readiness baseline to nights of the same statistic as the latest reading. When both sources
provide a reading for the same day, the merge retains Garmin's reading. Preserving both readings would let each
series build a baseline from all of its available nights.

SDNN and RMSSD are different quantities with no validated conversion, and wearable HRV is only meaningful against
the same device's own baseline. Garmin's nocturnal RMSSD is the better-supported input; Apple's passive nightly SDNN
has no nocturnal validation. Device scores (HRV status, Body Battery) are not independently validated. Research and
sources: `docs/design/hrv-sources.md`; evidence keys `hrv-metric-type`, `wearable-hrv-validity`, `hrv-nocturnal`,
`composite-scores`.

## Decision

1. `DailyMetrics` stores optional `hrvRMSSDMs` and `hrvSDNNMs` separately. The change must preserve or rebuild
   existing Garmin cache entries. `hrvNightlyAverageMs` becomes a computed value for display, reports and AI
   context, always shown with its metric.
2. `ReadinessRules` judges one series: the one with a baseline (≥ 14 of the last 60 nights) and ≥ 3 of the last 7;
   RMSSD when both qualify. Series are never mixed or converted. The reason names the metric and source.
3. A new source builds its own baseline. Today shows how many nights it still needs. The HRV signal is skipped
   when neither series qualifies.
4. Garmin's HRV baseline and status and Body Battery are context only, labelled as Garmin's.

## Consequences

- Someone wearing both watches can build each baseline from every available reading for that statistic.
- If a new watch has too little history and the previous series no longer qualifies, readiness skips the HRV signal.
- A second RMSSD source (another watch or ring) would need its own series or a source tag; deferred until needed.
