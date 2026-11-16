# Evidence register

Every rule in `Analytics` that recommends, proposes or evaluates something has an entry here (ADR-0012).
Levels: **strong** (meta-analyses / umbrella reviews / position stands built on them), **moderate** (RCTs or
low-certainty syntheses), **limited** (consensus, observational, mechanistic), **heuristic** (coaching default,
configurable). Keys are referenced from code as `EvidenceReference(key:level:)`.

## Menstrual cycle

### `cycle-phase-performance` — limited (no phase-based rules)
No influence of cycle phase on acute strength or resistance-training adaptations shown by current evidence;
performance possibly trivially lower in the early follicular phase, low-quality evidence; individual approach
recommended. → Cycle used only as context (ADR-0009).
Refs: Colenso-Semple et al. 2023 (umbrella review); McNulty et al. 2020 (meta-analysis). Reviewed 2026-11-16.

### `cycle-luteal-nutrition` — moderate
Meet carbohydrate needs in all phases; protein 1.4–2.2 g/kg/day, upper end in the luteal phase; energy
availability first. Refs: ISSN position stand, Sims et al. 2023. Reviewed 2026-11-16.

## Daily activity

### `walking-active-recovery` — moderate
Active recovery gives a small-to-moderate reduction in DOMS and perceived fatigue vs passive rest.
Refs: Dupuy et al. 2018 (meta-analysis, 99 studies). Reviewed 2026-11-16.

### `walking-no-interference` — strong
Interference scales with endurance-training frequency/duration; concurrent aerobic training does not
compromise hypertrophy or maximal strength (may blunt explosive strength). Low-intensity walking is below
that. Refs: Wilson et al. 2012; Schumann et al. 2022 (meta-analyses). Reviewed 2026-11-16.

### `low-steps-exercise-resistance` — moderate
≈ 5,000 steps/day or fewer blunted the metabolic response to exercise; ≈ 8,500 protected it.
Refs: Burton & Coyle 2021 (randomised crossover). Reviewed 2026-11-16.

### `walking-load-baseline` — heuristic
Only walking above the 28-day personal baseline counts as extra load; weight starts low and is configurable.
Reviewed 2026-11-16.

## Progression engine

### `progression-load-or-reps` — moderate
Progressing by adding reps at a fixed load and by adding load at fixed reps gave similar hypertrophy and
strength in trained lifters over 8 weeks (strength slightly favoured load, of questionable practical size).
→ Double progression is the default; rep progression is a valid way to progress.
Refs: Plotkin et al. 2022, PeerJ 10:e14142 (RCT). Reviewed 2026-11-16.

### `proximity-to-failure` — strong
Hypertrophy improves as sets end closer to failure; strength gains are similar across a wide range of RIR.
→ Default target RPE 8 (≈ 2 RIR) for hypertrophy work; strength work does not need to approach failure.
Refs: Robinson et al. 2024, Sports Med (dose-response meta-regression, 55 studies); Refalo et al. 2024 (RCT).
Reviewed 2026-11-16.

### `rir-based-rpe` — moderate
RPE scale anchored to reps in reserve (RPE = 10 − RIR). Loads for reps × RPE are derived from the estimated
1RM assuming a set of r reps at RIR behaves like a set of r + RIR to failure (Epley).
Refs: Zourdos et al. 2016, J Strength Cond Res; Helms et al. 2016. Reviewed 2026-11-16.

### `autoregulation-load` — moderate
Autoregulated (RPE/velocity) and percentage-based load prescription gave similar strength gains.
→ RPE-based scheme offered as an option, not as superior.
Refs: Hickmott et al. 2022, Sports Med Open 8:9 (meta-analysis, 15 studies). Reviewed 2026-11-16.

### `e1rm-estimation` — limited
Lifters under-predict reps to failure by ~1 rep on average and get less accurate in higher-rep sets.
→ e1RM uses sets of ≤ 12 reps; RPE < 6 is ignored (treated as a set to failure, a conservative estimate).
Refs: Halperin et al. 2022, Sports Med (meta-analysis). Cut-offs are heuristic. Reviewed 2026-11-16.

### `volume-dose-response` — strong
Weekly set volume has a positive dose-response with diminishing returns for hypertrophy (and smaller for
strength); counting indirect sets as 0.5 ("fractional") fits best. Per-session benefits plateau around ~11
fractional sets per muscle (preprint).
→ Effective sets per muscle use 1 / 0.5 weighting; stall suggestions add/remove a set relative to a
configurable 10–20 weekly fractional sets range (heuristic within the evidence).
Refs: Pelland et al. (meta-regressions, 67 studies, 2026); Remmert et al. 2025 (SportRxiv preprint).
Reviewed 2026-11-16.

### `deload-design` — limited
Expert Delphi consensus defines a deload as a period of reduced training stress to mitigate fatigue and
enhance preparedness; typically reduced volume and/or intensity of effort, not complete rest.
Refs: Bell et al. 2023, Sports Med Open 9:87. Reviewed 2026-11-16.

### `deload-cost` — moderate
A 1-week training break mid-programme slightly reduced lower-body strength gains and did not change
hypertrophy. → Deloads are proposed from fatigue signals, not on a timer alone, and reduce training instead
of stopping it. Refs: Coleman et al. 2024, PeerJ 12:e16777 (RCT). Reviewed 2026-11-16.

### `stall-heuristics` — heuristic
Stall = no e1RM gain > 1 % over the last 3 exposures vs the 6 before, with ≥ 2 missed targets. Linear reset
−10 % after 3 misses; microload at half the increment when the miss was by 1 rep; variation swap 3–4 weeks.
All configurable. Reviewed 2026-11-16.

### `rpe-creep` — heuristic
Same load and reps over 3 exposures with RPE up ≥ 1 point → accumulated fatigue signal (weight 1).
Reviewed 2026-11-16.

### `acwr` — heuristic
Acute:chronic workload ratio > 1.5 as a weak signal only; its injury-prediction validity is disputed.
Reviewed 2026-11-16.
