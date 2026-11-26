# 0047 — Muscle balance alerts for routines and training history

- **Status:** Proposed
- **Date:** 2026-11-26

## Context

Today `FocusBalance` knows one per-muscle rule: weekly fractional sets under 4 (`lowVolume`), and only for
hypertrophy and general goals. Nothing compares muscles with each other, nothing warns about too much volume, and
nothing looks at a routine or block *before* it is trained. An athlete can follow a badly balanced routine for
months without knowing. `Workload` compares the whole week with the usual week; it is not per muscle or region.

The model also limits what can be checked: `MuscleGroup.back` covers lats, upper back and rear delts, and
`shoulders` covers front, side and rear delts.

Research run on 2026-11-26 (three searches, summaries only; most full texts not read). Findings:

| Topic | What the evidence supports | Level |
| --- | --- | --- |
| Maintenance needs far less volume than growth; effort matters more than volume (Spiering 2021, narrative review; Bickel 2011, RCT) | "Under-trained" is a real concept | moderate |
| Exact maintenance threshold in sets/week | No study fixes one; ~4 fractional sets is a default | heuristic |
| Diminishing returns with weekly volume; fractional counting fits best (Pelland 2026, meta-regression) | Matches `volume-dose-response` | moderate |
| Harm from high volume | No solid evidence of harm in normal training; 12–20 sets/week is a common "moderate" band (Baz-Valle 2022) | limited |
| ~11 fractional sets per session plateau (Remmert 2025) | **Preprint; figures contradictory in secondary reports, not confirmed** | limited |
| Push:pull volume ratio preventing shoulder injury | No trial supports it. Evidence is on rotator-cuff strength in overhead athletes, not gym volume | heuristic |
| Rear delt responds best to reverse flies / rear-delt work (EMG, small samples) | EMG is not hypertrophy | limited |
| Need for both vertical and horizontal pulling | No outcome data | heuristic |
| Which muscles lag in recreational lifters | No population data | heuristic |
| Eccentric hamstring work (Nordic) cuts hamstring injuries by about half (van Dyk 2019 meta-analysis) | Mostly football, risk of bias | moderate (intervention) |
| Hamstring:quadriceps strength ratio predicts injury | Weak and inconsistent (Green 2020, Lee 2018 reviews) | limited |
| Upper/lower volume split | No evidence-based ratio | heuristic |
| Running vs strength volume | Concurrent training does not cancel maximal strength (Schumann 2022); no validated discount of kilometres into leg sets | moderate / heuristic |
| Core and forearms need direct sets | Limited evidence of benefit | limited |

## Decision

1. **A pure `MuscleBalance` analyzer** takes weekly fractional sets per muscle (and per session) and returns
   findings. It serves two surfaces with the same rules: a **plan audit** (sets projected from the block's routines
   and sessions per week, shown before training) and a **history audit** (logged sets, as `FocusBalance` does).
2. **Findings are suggestions, never changes** (as ADR-0013). They show their evidence level, can be dismissed,
   and are muted by a declared block that makes the pattern intentional (a specialization block).
3. **Wording is "balance", not "injury risk".** No finding claims to prevent injury.
4. **Initial rules and thresholds** (all configurable; levels as above):
   - *No direct work:* a tracked muscle with 0 direct sets in the window, any goal. *Under-trained:* under ~4
     fractional sets a week (heuristic; extends `lowVolume` to strength and hybrid goals).
   - *Excess:* soft notice from ~20–22 fractional sets a week per muscle, stronger from ~30; framed as "little
     extra benefit", not harm.
   - *Per session:* a suggestion to split when a muscle gets over ~10–12 fractional sets in one session. Limited
     until Remmert is confirmed.
   - *Pull vs push:* soft notice when weekly pull sets (rows and vertical pulls, excluding biceps) are under ~0.75×
     push sets (chest, shoulder press, triceps). Heuristic.
   - *Shoulder detail:* when push is above ~10 sets a week, ask for about 4–6 direct sets each of side and rear
     delts. Heuristic.
   - *Pulling patterns:* notice when a vertical or horizontal pull is missing for 2 weeks. Heuristic.
   - *Hamstrings:* quadriceps volume high and no hamstring work (knee flexion, hip hinge) for 3–4 weeks; worded as
     "no direct stimulus". Intervention evidence moderate, the alert itself limited.
   - *Lagging group:* a tracked muscle below ~40–50% of the user's own median. Based on the user's own volume,
     not on assumed weak points.
   - *Upper/lower:* only for a region at 0 sets. No ratio alert (no evidence).
5. **Not alerted:** frequency (volume-equated frequency does not change hypertrophy, `frequency-volume-equated`),
   core and forearms.
6. **Running is context, not sets.** Kilometres are shown beside leg findings but never converted into strength
   sets.
7. **Model change:** split `back` into lats and upper back, and `shoulders` into front, side and rear delts; add an
   optional movement pattern (vertical/horizontal push and pull, squat, hinge) to catalog exercises. Old data must
   keep decoding (tolerant decoding, as `AthleteProfile`).

## Consequences

- New file `Analytics/MuscleBalance.swift`, new `BalanceFinding`-style cases, texts in Spanish and English, and
  entries in `docs/evidence.md` (levels above) and further reading.
- `volume-dose-response` in `docs/evidence.md` says the ~11 per-session plateau without saying it is a preprint
  with unconfirmed figures: its level must be lowered when this is implemented.
- Catalog migration touches many built-in exercises; mapping review is real work.
- Thresholds are heuristics: validate them against real histories before they become visible, as for circadian
  timing.

## Pending verification before citing

Only van Dyk 2019, Schumann 2022, Huiberts 2024, Pelland 2026 (abstract), Spiering 2021, Baz-Valle 2022 and Remmert
2025 (abstract) were opened. Written from memory and still to check: Bickel 2011, Iversen 2021, Schoenfeld 2017,
Impellizzeri 2020, Green 2020, Lee 2018, Opar 2015/2021, Wilson 2012, Harøy 2019, Balsalobre-Fernández 2016,
Blagrove 2018, Beyer 2015, Cools 2015, the EMG papers (PMC7706677, PMC7734360, Rabello 2024) and the Schoenfeld
2025 lateral-raise study. The "Roberts 2021" and "Androulakis-Korakakis 2020" references from the brief could not be
identified and are dropped.
