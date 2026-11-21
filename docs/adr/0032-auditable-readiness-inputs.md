# 0032 — Auditable readiness inputs

- Status: accepted
- Date: 2026-11-21

## Context

Today's readiness light (ADR-0020) reported its reasons and, since ADR-0025, the coverage of the HRV series it
judged. It did not say where resting HR or sleep came from, why an input was skipped, or what each input was
compared with. Three gaps could also mislead the rule:

- Apple Health averages the day's HRV readings when a day has no sleep readings. Daytime SDNN runs lower than
  SDNN during sleep, so mixing both in one baseline could fake a drop.
- A zero, a non-finite value or an artefact (900 ms, 220 bpm) counted like any other reading.
- When a watch stopped syncing, its series vanished from the result without a trace, and an older check-in was
  dropped silently.

## Decision

1. `Readiness.inputs` lists one `ReadinessInputAudit` per input, in a fixed order: every HRV series with data
   (the judged one first), resting HR, sleep, check-in. Each records source, status, latest day, the value
   judged, recent coverage, rejected readings, the reference (personal baseline, cycle-phase baseline or fixed
   threshold, with its days, readings and minimum) and the outcome (below, within, above).
2. Statuses keep missing, stale and out-of-range apart: `missing` (nothing in the window read), `stale` (values,
   but none recent enough), `outOfRange` (only implausible values), `buildingBaseline`, `tooFewRecent`,
   `anotherSeriesUsed` and `compared`. An earlier value never stands in for today's resting HR or sleep.
3. An HRV series is a statistic read with one protocol: whole-night RMSSD, SDNN during sleep and daytime SDNN
   (`HRVSeriesID`). `DailyMetrics.hrvSDNNWindow` records the protocol; data written before this ADR has no value
   and is read as sleep. Device switches stay visible because each source reports its own statistic (ADR-0025).
4. Plausible ranges, all in `ReadinessRules.Settings`: HRV 3–300 ms, resting HR 25–150 bpm, sleep above 0 and
   at most 18 h. Readings outside them are ignored and counted. The low-night count therefore uses the eligible
   measured nights as its denominator.
5. Baseline overlap: the 60-day baseline includes the six earlier nights of the seven-night trend window. The rule
   keeps them, as the HRV-guided studies behind `readiness-hrv` compare a rolling mean with a rolling normal
   range, and records the overlap in `ReadinessReference.overlappingReadings`. Changing this policy is a rule
   change that needs evidence first. The seven-day averages Today shows are display summaries, not this baseline.
6. `DailyMetrics` keeps the source of resting HR and sleep through a merge (`restingHeartRateSource`,
   `sleepSource`). A single-source day without them infers its source, so older Garmin caches need no migration.

## Consequences

- Reports list every input with its provenance, and Today explains a skipped HRV comparison when a series is
  stale or implausible. The explanatory card (backlog task 4) can build on the same audit.
- Someone whose Apple Watch alternates sleep and daytime readings builds two smaller baselines; until one has 14
  readings the HRV comparison is skipped and says why.
- New fields are optional; `Readiness` is not persisted, and `DailyMetrics` decodes from older Garmin caches
  unchanged. Backups do not contain these types.
- Device identity within one source (two Apple Watches) is not available from Apple Health and is not tracked.
