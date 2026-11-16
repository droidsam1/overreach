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
