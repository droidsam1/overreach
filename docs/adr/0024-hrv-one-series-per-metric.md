# 0024 — HRV: one series per metric, never a mixed baseline

- **Status:** Proposed
- **Date:** 2026-11-20

## Context

Apple Watch writes nightly HRV to Health as SDNN from a few spot readings; Garmin's Personal API gives the
whole-night average RMSSD (ADR-0022). Both currently go into `DailyMetrics.hrvNightlyAverageMs`, and the per-day
merge fills Garmin's gaps with Apple's value, so `ReadinessRules` can build one baseline out of two metrics from two
devices. The same happens when someone changes watch.

SDNN and RMSSD are different quantities with no validated conversion, and wearable HRV is only meaningful against
the same device's own baseline. Garmin's nocturnal RMSSD is the better-supported input; Apple's passive nightly SDNN
has no nocturnal validation. Device scores (HRV status, Body Battery) are not independently validated. Research and
sources: `docs/design/hrv-sources.md`; evidence keys `hrv-metric-type`, `wearable-hrv-validity`, `hrv-nocturnal`,
`composite-scores`.

## Decision

1. `DailyMetrics` stores `hrvRMSSDMs` and `hrvSDNNMs` separately (optional; `DailyMetrics` is rebuilt from sources
   and not in backups, so no format change). `hrvNightlyAverageMs` becomes a computed value for display, reports and
   AI context, always shown with its metric.
2. `ReadinessRules` judges one series: the one with a baseline (≥ 14 of the last 60 nights) and ≥ 3 of the last 7;
   RMSSD when both qualify. Series are never mixed or converted. The reason names the metric and source.
3. A new source starts its own baseline; until it has one, the HRV signal is skipped and Today says how many nights
   are still needed.
4. Garmin's HRV baseline and status and Body Battery are context only, labelled as Garmin's.

## Consequences

- A person with both watches, or who changes watch, no longer gets a false "HRV below normal" from a metric switch.
- Someone changing from Apple Watch to Garmin without the 60-day backfill loses the HRV signal for about two weeks.
- A second RMSSD source (another watch or ring) would need its own series or a source tag; deferred until needed.
