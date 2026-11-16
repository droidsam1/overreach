# 0009 — Menstrual cycle: context for the engine, not fixed phase rules

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Overreach should serve women as well as men. Many apps prescribe fixed phase-based training ("luteal phase →
lower the loads", "late follicular → push PRs"). The research does not support that:

- Colenso-Semple et al. (2023), umbrella review: current evidence shows no influence of menstrual cycle phase
  on acute strength performance or on adaptations to resistance training. Most studies verify phases poorly.
- McNulty et al. (2020), meta-analysis of 78 studies: performance may be *trivially* lower in the early
  follicular phase (ES ≈ −0.06); the evidence quality is low, so general guidance cannot be given and an
  individual approach is recommended.
- Some physiology does shift reliably and affects *our* signals: in the luteal phase nightly HRV tends to be
  lower and resting HR and body temperature higher. Rules built on a single baseline would flag those normal
  shifts as poor recovery.
- Nutrition: the ISSN position stand on female athletes (2023) recommends meeting carbohydrate needs in every
  phase and protein at the upper end of 1.4–2.2 g/kg/day in the luteal phase; energy availability matters
  more than any phase tweak.

## Decision

1. The cycle is **context**, never a fixed rule. No load, volume or rest change is made from the calendar
   alone.
2. Profile: `sex` (female / male / unspecified) and `cycleTracking` (off / natural cycle / hormonal
   contraception / peri- or post-menopause). Both optional; asked in onboarding, editable in Settings.
3. Cycle data is read from Apple Health (`menstrualFlow` and symptom types, written by the Health app's
   Cycle Tracking, Flo, Clue…) through a `CycleSource` protocol, plus a manual "period started today"
   entry in the daily check-in. We do not build a cycle tracker. Garmin's Women's Health API is
   enterprise-only and is out of scope.
4. Phase estimation is a pure, tested function in `Analytics` with a confidence level, not a medical claim.
5. Uses, in order of value:
   - **Phase-aware baselines** for HRV and resting HR, so luteal shifts don't trigger false deloads.
   - **Symptom-driven autoregulation** (RPE-based targets on bad days), not calendar-driven cuts.
   - **Personal pattern detection** after ≥ 3 logged cycles: adjust only if this user's data shows a
     consistent per-phase difference.
   - Context in the shareable report, so ChatGPT/Claude can take it into account.
6. Hormonal contraception or menopause disables phase estimation (symptoms are still logged).

## Consequences

- No "cycle syncing" marketing features; every adjustment shows its reason and the evidence level.
- Reproductive health data stays on the device like everything else; it is only included in a report if the
  user enables it.
- Design details and phase placement: `docs/design/cycle-aware-training.md`.

## References

- Colenso-Semple LM et al. *Front Sports Act Living* 2023;5:1054542. doi:10.3389/fspor.2023.1054542
- McNulty KL et al. *Sports Med* 2020;50:1813–1827. doi:10.1007/s40279-020-01319-3
- Elliott-Sale KJ et al. (oral contraceptives) *Sports Med* 2020;50:1785–1812. doi:10.1007/s40279-020-01317-5
- Sims ST et al. ISSN position stand: nutritional concerns of the female athlete. *J Int Soc Sports Nutr*
  2023;20:2204066. PMID 37221858
