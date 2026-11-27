# 0047 — Muscle balance alerts for routines and training history

- **Status:** Accepted
- **Date:** 2026-11-26

## Context

Today `FocusBalance` knows one per-muscle rule: weekly fractional sets under 4 (`lowVolume`), and only for
hypertrophy and general goals. Nothing compares muscles with each other, nothing warns about too much volume, and
nothing looks at a routine or block *before* it is trained. An athlete can follow a badly balanced routine for
months without knowing. `Workload` compares the whole week with the usual week; it is not per muscle or region.

The model also limits what can be checked: `MuscleGroup.back` covers lats, upper back and rear delts, and
`shoulders` covers front, side and rear delts.

The [evidence register](../evidence.md#muscle-balance) records the support and limits for each rule.
Weekly volume has a dose-response with diminishing returns. Most thresholds for identifying muscle
or movement imbalances are heuristics. Frequency, direct core and forearm work, and a preferred
upper-to-lower set ratio fall outside the audit.

## Decision

1. **A pure `MuscleBalance` analyzer** takes weekly fractional sets per muscle (and per session) and returns
   findings. It serves two surfaces with the same rules: a **plan audit** (sets projected from the block's routines
   and sessions per week, shown before training) and a **history audit** (logged sets, as `FocusBalance` does).
2. **Findings are suggestions, never changes** (as ADR-0013). They show their evidence level, can be dismissed,
   and are muted by a declared block that makes the pattern intentional (a specialization block).
3. **Wording is "balance", not "injury risk".** No finding claims to prevent injury.
4. **Initial rules and thresholds.** Thresholds are configurable. See the evidence register for levels.
   - *No direct work:* a tracked muscle with 0 direct sets in the window, any goal. *Under-trained:* under ~4
     fractional sets a week (heuristic; extends `lowVolume` to strength and hybrid goals).
   - *Excess:* soft notice from ~20–22 fractional sets a week per muscle, stronger from ~30; framed as "little
     extra benefit", not harm.
   - *Per session:* a suggestion to split when a muscle gets over ~10–12 fractional sets in one session. Limited.
     Remmert et al. estimated a detectability limit of 11 fractional sets for hypertrophy in a preprint.
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

- The analyzer lives in `Analytics/MuscleBalance.swift`. Findings have texts in English, Spanish and Galician
  and link to the evidence register.
- Catalog migration touches many built-in exercises; mapping review is real work.
- Thresholds are heuristics: validate them against real histories before they become visible, as for circadian
  timing.

## Reference verification

Reviewed on 2026-11-27. The evidence register links the source publications for each rule.
The following papers were checked for applicability and excluded from the rule citations.

- [Impellizzeri et al. 2020](https://andrewvigotsky.com/studies/Impellizzeri_2020_Sports_Med_ACWR.pdf)
  studied acute-to-chronic workload ratio artifacts. It provides no muscle volume cutoff.
- [Harøy et al. 2019](https://bjsm.bmj.com/content/53/3/150) tested an adductor exercise intervention
  in male football players. Its outcome was groin problems.
- [Beyer et al. 2015](https://pubmed.ncbi.nlm.nih.gov/26018970/) compared two treatments for
  Achilles tendinopathy. Its results apply to that clinical population.

The minimum-dose strength review was identified as Androulakis-Korakakis et al. (2020) and cited
for 1RM gains. The brief's “Roberts 2021” citation could not be identified from the author, year
and topic.

## Rollout validation

One real backup was replayed on 2026-11-27. Four rules fired in more than half of that history's assessed
weeks. This is a single-participant result. Keep the current thresholds under review and the new findings hidden
until the replay includes several participants. Record cohort-level rates here once that data is available.
Use one Overreach backup per consenting participant. From the repository root, run:

```shell
swift run --package-path Packages/OverreachCore muscle-balance-replay /path/to/backup-a.json /path/to/backup-b.json
```

The replay uses the current built-in catalog and saved custom mappings, the backup's goal and
declared blocks, and the production history analyzer. It assesses every completed UTC calendar
week from the first eligible session through the export date. The analyzer evaluates its usual
rolling windows as of each week's end. Weeks without analyzable recent training and participants
without any assessed weeks are excluded. Older exports or incomplete mappings can limit coverage.
Running distance is absent from a portable backup and does not affect whether a rule fires.

The CSV reports how many participants and assessed weeks triggered each rule at least once. Use
the included denominators to record rates, check which rules fire for most participants, and review
the flagged cases for context before adjusting the thresholds or enabling findings. Keep the
backups local and record only aggregate counts in this ADR. A synthetic smoke test with
format-1 and format-2 backups verified the participant and weekly counters, including zero-count
rules. Rollout requires the real-history results.
