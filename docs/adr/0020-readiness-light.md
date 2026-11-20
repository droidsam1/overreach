# ADR-0020: The readiness light compares today with the person's own baseline

- Status: accepted
- Date: 2026-11-19

## Context

Today showed "Unknown" for every day: the traffic light had a type (`Readiness`) but no rules. The light has to
answer "train hard, easy, or rest?" from whatever the user's devices provide (Apple Watch gives SDNN HRV, Garmin
via Health gives resting HR and sleep but no HRV, an iPhone alone gives neither) plus an optional check-in, and
explain itself (ADR-0012).

## Decision

1. `Analytics.ReadinessRules` is a pure function of the merged daily metrics, today's check-in and `Settings`.
2. Each signal is judged against the person's own history, never a population norm: HRV as the 7-day rolling ln
   average against mean ± 0.5 SD of the previous 60 days; resting HR against its 60-day mean; sleep against a
   configurable floor; energy and soreness from the check-in. Baselines need 14 nights; until then the signal is
   skipped, not guessed.
3. Combination: sick → red; no signal → green; any signal → amber; red needs two signals and at least one of HRV
   or resting HR, so a short night and a tired feeling alone never say "rest". Nothing to judge → unknown.
4. Every reason carries its evidence key (`docs/evidence.md`, "Readiness"); Today shows each reason with its level.
5. Today loads 60 days of metrics for the baselines and still shows the last 7.

## Consequences

- The light works with partial data and gets better as history accumulates; with no data it says what it needs.
- HRV-guided training has moderate evidence for endurance and none so far for strength, so the light moderates
  intensity; it does not change the strength plan by itself.
- The check-in sheet on Today (energy, soreness, sick, note) feeds the subjective signals.
- Not yet: phase-aware baselines (ADR-0009), a personal sleep baseline, and settings to change the thresholds.
  Garmin HRV feeds the light since ADR-0022, judged only against nights of the same statistic (ADR-0024). Each slots into `ReadinessRules.Settings` or its inputs.
