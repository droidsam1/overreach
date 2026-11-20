# Evidence review — November 2026

A full pass over every rule, threshold, metric and user-facing text in Overreach against the most recent
high-quality evidence (ADR-0012). It also maps each topic to further reading for the user, including Fitness
Revolucionario (Marcos Vázquez) where it agrees with the evidence (proposal: ADR-0030).

- **Scope:** `Analytics` (progression, stalls, deloads, focus, blocks, plan follow-up, warm-ups, workload,
  readiness), the metrics in `DailyMetrics` and how Today and the logger present them, and the design docs for
  phases 2–3 (cycle, daily activity, run/lift).
- **Method:** each register entry was re-checked for newer meta-analyses, position stands and RCTs (searches up
  to 2026-11-20); each rule in code was compared with its entry; each metric was checked for measurement validity,
  not only for what it means physiologically.
- **Verdicts:** ✅ aligned · 🟡 aligned, wording or level to adjust · 🟠 change recommended · 🔴 fix before
  relying on it.

## Status (2026-11-20)

All of §8 is implemented: the uncoupled weekly load comparison (`weekly-load-change`), one HRV statistic per
baseline (done on main as `HRVMetric`, ADR-0024 and ADR-0025, which this branch adopted instead of its own version)
and the natural-cycle HRV note (`hrv-cycle-phase`), effective sets from RPE 6
(`effective-set-threshold`), the wording and level changes, the "watch estimate" labels on Today, and further
reading (ADR-0030, accepted). Still open: the Fitness Revolucionario links were located through a search index
because the site could not be reached from the development environment; read each one before a release
(`scripts/check-reading-links.py` from a normal network checks they resolve). Rules for run/lift, muscle recovery
and steps (§2.4, §7) are for the phases that build them.

## 1. Summary

The foundation is good. Most rules follow the best current syntheses, heuristics are labelled, and the readiness
light already does the two things the literature most supports: compare with the person's own baseline and use a
rolling HRV average. The problems are in four places:

1. 🔴 **Acute:chronic workload ratio.** `Workload.acuteChronicRatio` is the *coupled* 7:28 ratio (the acute week
   is inside the chronic window), the variant shown to create spurious correlations, and the ACWR's link to injury
   has been seriously challenged. Its doc comment ("values above ~1.3–1.5 suggest load is rising too fast")
   claims more than the evidence. It is not wired into a caller yet; fix it before it is.
2. 🟠 **Mixed HRV metrics in one baseline.** Metrics merge per day with Garmin first and Apple Health second. A
   user with both devices gets Garmin RMSSD on most nights and Apple Watch SDNN on the nights Garmin misses, and
   the readiness baseline averages them as if they were one measure. They are different measures on different
   scales.
3. 🟠 **Effective sets drop everything under RPE 7.** `StrengthMetrics.effectiveSets` counts a set as 0 below RPE 7.
   The latest dose-response work shows hypertrophy falls *gradually* with distance from failure, and strength
   barely depends on it. The cut-off has no register entry.
4. 🟡 **Wearable numbers shown without their reliability.** Today shows deep and REM sleep, and the data model
   carries Body Battery, sleep score, stress, Training Readiness and VO2max. Consumer sleep staging agrees only
   fairly to moderately with polysomnography, and the composite scores have no independent validation. None of
   them drives a rule today (correct); the UI should say how much to trust them.

Smaller items: a few evidence levels are higher than the evidence (§4), the red-light text is stronger than the
evidence for strength training, the planned muscle-group recovery windows in `product.md` are not evidence-based,
and two Fitness Revolucionario articles that look relevant contradict current evidence and must not be linked
(§6).

## 2. Rule-by-rule review

### 2.1 Progression engine

| Key | Rule in code | Verdict | Notes |
| --- | --- | --- | --- |
| `progression-load-or-reps` | Double progression is the default; rep and load progression both valid | ✅ | Plotkin et al. 2022 is still the only direct RCT. |
| `proximity-to-failure` | Default RPE 8 (hypertrophy 8.5); strength need not approach failure | ✅ | Robinson et al. 2024 (Sports Med 54(9), meta-regressions) is the newest synthesis: hypertrophy improves closer to failure, strength similar over a wide RIR range. Refalo et al. 2023 (Sports Med 53(3), 15 studies) found only a trivial advantage of failure; Refalo et al. 2024 RCT (J Sports Sci) found 1–2 RIR ≈ failure for quadriceps growth in trained people. Add both Refalo papers to the entry: they support *not* going to failure by default. |
| `rir-based-rpe`, `rir-estimation`, `rir-calibration` | RPE = 10 − RIR; bias warning; occasional calibration | ✅ | Unchanged literature. |
| `autoregulation-load` | RPE scheme as an option, not as superior | ✅ | Hickmott et al. 2022 still the best synthesis. |
| `e1rm-estimation` | Epley with RIR added; sets ≤ 12 reps; RPE < 6 ignored | 🟡 | Epley comes from a poundage chart, not a validation study; accuracy drops above ~10 reps and differs by exercise and person. Fine for *trends within one exercise*; never present e1RM as a true 1RM. Note: `StrengthMetrics.estimatedOneRepMax` (plain Epley, no rep cap) coexists with `LoadPrescription.estimatedOneRepMax` (capped, RIR-aware); whatever shows "estimated 1RM" to the user should use the capped one. |
| `volume-dose-response` | Fractional sets (1 / 0.5); 10–20 weekly sets range for add/remove-set suggestions | ✅ | **Pelland et al. is now published:** Sports Med 2026;56(2):481–505. Confirms fractional counting, diminishing returns, steeper flattening for strength, and frequency effects only for strength. Remmert et al. 2025 (per-session plateau ~11 sets) is still a preprint: keep it labelled so. |
| *(none)* | `effectiveSets` counts a set only if RPE ≥ 7 (or no RPE) | 🟠 | No register entry. Robinson 2024 describes a continuous decline, not a cliff at 3 RIR. Options: (a) register it as `effective-set-threshold` (heuristic) and lower the cut-off to RPE 6 (≈ 4 RIR), or (b) weight sets by RIR. (a) is simpler and honest; (b) is over-precise given RIR estimation error (~1 rep). Recommend (a). |
| `stall-heuristics` | e1RM +1 % over 3 vs 6 exposures, ≥ 2 misses; resets, microloads, swaps | ✅ | Heuristic, labelled, configurable. No trial defines a stall. |
| `rpe-creep` | Same load/reps, RPE +1 over 3 exposures | ✅ | Heuristic; consistent with the RPE-based fatigue logic of autoregulation. |
| `deload-design`, `deload-cost` | Proposal from fatigue signals; −50 % sets, −10 % load, RPE ≤ 7, 1 week | ✅ | Matches the Delphi definition (Bell et al. 2023) and what trained lifters actually do: Rogerson et al. 2024 (Sports Med Open, n = 246) — deloads of ~6 days every ~5–6 weeks, cutting volume and load and raising RIR while keeping frequency and exercises. No new deload RCT since Coleman 2024. Add Rogerson 2024 as practice data (limited). |
| *(mismatch)* | `DeloadSignal.weeksSinceDeload` cites `deload-cost` | 🟡 | `deload-cost` is about the cost of a full week off. The interval signal is supported by practice data (Rogerson 2024) and the Delphi consensus: cite `deload-design` (or a new `deload-practice`). |
| `acwr` | Coupled 7:28 rolling sums, > 1.5 as a weak deload signal | 🔴 | See §3.1. |

### 2.2 Training focus, blocks and plans

| Key | Verdict | Notes |
| --- | --- | --- |
| `loading-by-goal` | ✅ | Unchanged. |
| `rest-hypertrophy` | ✅ | Singer et al. 2024 is still the newest meta-analysis: > 60 s helps a little, nothing clear beyond ~90 s. The rest timer starts at the lower bound (90 s): good. |
| `rest-strength` | ✅ | Only one RCT (Schoenfeld 2016) plus older reviews; level "moderate" is fair. |
| `periodization` | 🟡 | Moesgaard et al. 2022 is still the newest meta-analysis; no newer synthesis found. It is one meta-analysis with heterogeneous, short studies: "moderate" is a more honest level than "strong". The rule (block suggestions for strength goals, optional for hypertrophy) is right. |
| `focus-heuristics` | ✅ | Labelled heuristic. |
| `frequency-volume-equated` | ✅ | Pelland 2026 refines it: with volume equated, frequency still has a small effect on **strength** (not hypertrophy). The "fewer, fuller sessions" proposal stays right for hypertrophy; for strength goals the text should not promise "no difference". |
| `retraining-after-break`, `illness-return`, `plan-adherence` | ✅ | Unchanged. |

### 2.3 Warm-up

`warm-up-general`, `warm-up-specific`, `warm-up-ramp`: ✅ Correctly avoids the retracted 2026 scoping review.
Static stretching is (correctly) not suggested before lifting.

### 2.4 Cycle, walking and future run/lift rules

| Key | Verdict | Notes |
| --- | --- | --- |
| `cycle-phase-performance` | ✅ | Colenso-Semple 2023 umbrella review remains the reference; no phase-based rules is right. |
| `cycle-luteal-nutrition` | ✅ | For the future nutrition module. |
| *(gap)* cycle and HRV | 🟠 | Vagally mediated HRV drops from follicular to luteal phase (Schmalenberger et al. 2019, J Clin Med, 37 studies, d = −0.39), driven by progesterone. Until phase-aware baselines exist (ADR-0009), a naturally cycling user can get amber/red in every late luteal phase for a normal change. Interim fix: when cycle tracking is on and the phase is luteal, the HRV reason says "possible luteal shift" and does not count toward red. |
| `walking-active-recovery` | ✅ | |
| `walking-no-interference` | 🟡 | The evidence is about structured endurance training; applying it to walking is an extrapolation (in the safe direction). "Moderate" fits better than "strong". |
| `low-steps-exercise-resistance` | 🟡 | One randomised crossover. Add the health-outcome evidence for step messages: Ding et al. 2025 (Lancet Public Health 10:e668, 57 studies) — benefits rise steeply up to ~5,000–7,000 steps/day and keep rising more slowly; 7,000 vs 2,000 steps ≈ 47 % lower all-cause mortality (moderate certainty). |
| *(planned)* run/lift interference | — | Schumann et al. 2022 (Sports Med 52:601): concurrent aerobic training does not blunt hypertrophy or maximal strength, running or cycling; it can blunt **explosive** strength, more when both are in the same session than when separated by ≥ 3 h. Eddens et al. 2018: within one session, strength first favours lower-body strength. Short, easy aerobic work (≤ 30 min, low intensity) barely affects strength in the following session. This is what the "run or lift?" rules in phase 3 should build on. |
| *(planned, product.md)* muscle recovery 48–72 h legs/back, 24–48 h arms | 🟠 | Not evidence-based as fixed per-muscle windows. Recovery depends mostly on effort and volume: sessions to failure or with many reps per set keep mechanical performance down for 24–48 h, while the same work stopped short of failure recovers in ~6–24 h (Morán-Navarro et al. 2017; González-Badillo et al. 2016; Pareja-Blanco et al. 2020). Model fatigue from RIR and sets, label it heuristic. |

### 2.5 Readiness light

| Key | Verdict | Notes |
| --- | --- | --- |
| `readiness-hrv` | 🟠 | The method (ln HRV, 7-day rolling mean vs mean ± 0.5 SD of the baseline) follows Plews and Vesterinen. No HRV-guided-training meta-analysis newer than 2021 was found; the conclusion stands (small or no benefit for endurance performance, none shown for strength). Issues: (1) mixed RMSSD/SDNN baselines (§3.2); (2) on days without sleep data, the Apple value is the mean of daytime samples, a different context from nocturnal values; (3) Apple Watch SDNN comes from short PPG windows: a 2024 modelling study (Dewig et al., Sports Med) argues PPG-derived HRV is a different signal from ECG HRV, not a noisy copy — personal-trend use is fine, cross-device comparison is not; (4) the luteal shift (§2.4). |
| `readiness-resting-hr` | ✅ | The 5 bpm cut-off is a labelled heuristic. Consider expressing it against the person's variability (e.g. ≥ 1 SD *and* ≥ 3 bpm) so it works for people with very stable or very noisy resting HR; keep 5 bpm as the fallback. |
| `readiness-sleep` | ✅ | Fixed 6 h floor is honest for now; personal sleep baseline is the planned refinement. |
| `readiness-subjective` | ✅ | Saw et al. 2016 is still the reference. Note: soreness (DOMS) is a poor marker of muscle damage or growth; a 3/3 soreness signal should moderate *that* muscle's work more than the whole day. |
| `readiness-combination` | 🟡 | Logic is sound (physiology needed for red; subjective/sleep alone never red). Text: red says "Rest or go for a walk today." For strength training there is no evidence that HRV-guided rest days help, and the deload literature favours reduced training over stopping. Suggest: "Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE ≤ 6)." Sick stays "rest until the symptoms ease". |

## 3. Findings that need code

### 3.1 🔴 Replace the coupled ACWR

- **Evidence:** Lolli et al. 2019 (BJSM 53:921): the coupled ratio creates a spurious acute–chronic correlation;
  Impellizzeri et al. 2020 (IJSPP) and 2021 (Sports Med 51:581, "Time to dismiss ACWR and its underlying theory"):
  the injury association is largely an artefact of the ratio; window lengths are arbitrary; EWMA variants are
  very sensitive to missing data (common in a personal app). A 2019 case study (elite basketball and
  weightlifting) found the coupling effect trivial in its data, so the debate is not closed, but nothing supports
  a 1.5 threshold.
- **Recommendation:** keep the *concept* the user needs ("this week's load is well above your usual") without the
  ratio: compare the last 7 days with the mean of the **previous** 3 weeks (uncoupled), show it as "% vs your
  usual week", label it `heuristic`, keep its deload weight at most 1, and remove the injury-flavoured threshold
  wording from the doc comment. Update `acwr` in `docs/evidence.md` with these references. Never present it as
  injury risk.

### 3.2 🟠 One HRV metric per baseline

- Store which metric a nightly HRV value is (`rmssd` from Garmin, `sdnn` from Apple Watch) and compute baselines
  per metric. If a person has both, prefer the source with more nights in the baseline window and do not fill gaps
  from the other.
- Prefer sleep-window samples; when a day has no sleep data, skip the HRV value for that day rather than use
  daytime samples (or keep it out of the baseline).

### 3.3 🟠 Effective-set cut-off

Lower `minimumRPE` to 6 and register it as `effective-set-threshold` (heuristic, cites Robinson 2024 and
Pelland 2026). Sets without RPE keep counting.

### 3.4 🟡 Wording

- Red readiness text (§2.5).
- Frequency proposal: avoid "no difference" for strength goals (§2.2).
- e1RM: label as "estimated" everywhere, never "your 1RM".

## 4. Evidence levels to adjust

| Key | Now | Suggested | Why |
| --- | --- | --- | --- |
| `periodization` | strong | moderate | One meta-analysis, short heterogeneous studies; effect only for 1RM. |
| `walking-no-interference` | strong | moderate | Extrapolated from endurance training to walking. |
| `readiness-hrv` | moderate | moderate (keep) but say "limited for strength" in the text | No strength benefit shown. |

Changing a level means changing the `EvidenceReference` in code and the register together.

## 5. Biomarkers and wearable metrics

How each metric in `DailyMetrics` should be used, given what is known about its *measurement*.

| Metric | Source | Validity | Use in Overreach |
| --- | --- | --- | --- |
| Nightly HRV | Garmin (RMSSD, overnight) · Apple Watch (SDNN, PPG spot readings) | Good for personal trends with a rolling average; poor across devices and metrics. Overnight wearable HRV agrees with chest straps to varying degrees (small 2025 comparison: Oura and Whoop closer than older Garmin and Polar devices). Luteal phase lowers it. | Rule input (readiness), one metric per baseline, 7-day average, never a single night. |
| Garmin HRV status and baseline | Garmin | Proprietary but transparent in concept (personal baseline band). | Context only; our own band is the rule. |
| Resting HR | Both | Reliable as a daily trend; rises with short-term overload, illness, heat, alcohol, luteal phase. | Rule input (readiness). |
| Sleep duration | Both | Sleep vs wake detection is good (> 90 % sensitivity) but wake is under-detected, so total sleep is often overestimated. | Rule input with a conservative floor. |
| Sleep stages (deep, REM, light) | Both | Fair to moderate agreement with polysomnography (κ ≈ 0.2–0.5 across six wrist devices, Schyvens et al. 2025, Sleep Advances); Apple Watch S8 underestimated deep sleep by ~43 min in a 2024 study. | Display only, with "estimated by your watch"; never a rule input. |
| Sleep score, Body Battery, stress, Training Readiness, training status, recovery time | Garmin | Proprietary composites. No independent validation found; vendors validate sensors, not scores. | Context only, labelled as Garmin's. Never a rule input, never combined with our light. |
| VO2max | Both | Exercise-based estimates are acceptable for groups but have wide individual error (Molina-García et al. 2022, Sports Med, INTERLIVE; resting-based estimates overestimate). | Long-term trend only. |
| Acute load, training effect | Garmin | Proprietary (TRIMP/EPOC-based). | Could feed run load (phase 2) labelled as Garmin's estimate. |
| Respiration rate, SpO2 | Both | Nocturnal respiration rate is fairly stable and rises with illness; consumer SpO2 is imprecise. | Possible future illness hint (limited evidence); not now. |
| Steps | Both | Good at normal walking speeds. | Baseline-relative load and health messaging (Ding 2025). |
| Max HR from 220 − age | (not used) | Error of ±10–12 bpm for individuals. | If HR zones are added, prefer measured max HR or HR reserve/lactate-threshold HR from the watch; never 220 − age silently. |

Presentation rule that follows: **every number on screen tells the user whether it is measured, estimated by the
watch, or computed by Overreach,** and only the first and last kinds feed rules.

## 6. Further reading — map for ADR-0030

Fitness Revolucionario articles were located through a search index; the site could not be fetched from the
development environment, so each link must be opened and read before it ships. "Agrees" means the summary found
agrees with the register entry.

| Topic (keys) | Primary (open access where possible) | Fitness Revolucionario (es) | Status |
| --- | --- | --- | --- |
| Effort, RIR/RPE, autoregulation (`proximity-to-failure`, `rir-*`, `autoregulation-load`) | Robinson et al. 2024; Refalo et al. 2023 | "Autorregulación: usa tus percepciones para mejorar tu entrenamiento" (2020-07-29) | Agrees (RPE 8–9, RIR, autoregulation) |
| Progressive overload, double progression (`progression-load-or-reps`) | Plotkin et al. 2022 (PeerJ, open) | "Qué es el entrenamiento de fuerza y cómo empezar" (2022-10-08) — an extra rep at the same load counts as progress | Agrees |
| Volume, frequency, rep ranges (`volume-dose-response`, `frequency-volume-equated`, `loading-by-goal`) | Pelland et al. 2026 | "Cómo ganar masa muscular" (guide, /ganar-musculo/) — ≥ 4 sets/muscle/week, 6–15 reps at RIR 1–2, twice a week | Agrees |
| Linear vs undulating, waves (`periodization`, rep cycle) | Moesgaard et al. 2022 | "¿Cuántas repeticiones para hipertrofiar?" (2016-08-25); "Aumenta tu fuerza y musculatura con 5/3/1" (2013-06-03) as an example of wave loading | Agrees, but old: check the rest-interval passage before linking |
| Rest between sets (`rest-*`) | Singer et al. 2024 (Frontiers, open) | Older FR guide says shorter rests give more hypertrophy | **Do not link** — contradicts Singer 2024 and Schoenfeld 2016 |
| Deloads (`deload-*`) | Bell et al. 2023 (Sports Med Open, open); Rogerson et al. 2024 (open) | No dedicated article found | Primary only |
| Sleep (`readiness-sleep`) | Walsh et al. 2021 consensus | "Entrenamiento invisible: estrategias para acelerar la recuperación (sueño)" (2021-08-23) | Agrees |
| HRV (`readiness-hrv`) | Plews et al. 2012; Düking et al. 2021 | "¿Por qué quieres un corazón irregular?" (2016-02-13); "Mejorando la recuperación… aumenta tu HRV" (2016-05-05) | Partly: good introduction, but "high HRV = recovered" is simpler than the rolling-baseline method; link with a one-line note |
| Soreness (`readiness-subjective`) | Saw et al. 2016 | "La ciencia de las agujetas" (2019-01-10) | Agrees |
| Easy runs, zone 2 (amber text) | Schumann et al. 2022 | "Mejora tu VO₂máx para vivir más: zona 2, HIIT y más" (2023-08-13) | Agrees on zone 2 and talk test; ignore its 220 − age formula |
| Cardio and strength together (planned run/lift) | Schumann et al. 2022 | "¿Cardio o pesas para adelgazar?" (2022-03-03) | Agrees in general |
| Walking and steps (`walking-*`, `low-steps-*`) | Ding et al. 2025 | "La magia de caminar, y consejos para dar más pasos" (2014-03-08) | Agrees on the message; numbers are older — pair with Ding 2025 |
| Menstrual cycle (`cycle-*`) | Colenso-Semple et al. 2023; McNulty et al. 2020 | "Utiliza tu ciclo menstrual para entrenar y comer mejor" (2016-02-21) recommends phase-based training | **Do not link** — contradicts current evidence and ADR-0009 |
| Warm-up (`warm-up-*`) | Fradkin et al. 2010 | "Qué es el entrenamiento de fuerza…" (2022) — ~5 min general warm-up, no static stretching before | Agrees |
| Illness (`illness-return`) | Schwellnus et al. 2022 (IOC) | — | Primary only |

For English users, add a reputable English explainer per topic later (e.g. Stronger by Science articles written
by the same authors as several of the meta-analyses).

## 7. Proposed register entries (ready to paste when the rules land)

- `effective-set-threshold` — heuristic. Sets count toward weekly volume from RPE 6 (≈ 4 RIR). Hypertrophy declines
  gradually with distance from failure and strength barely depends on it (Robinson 2024; Pelland 2026); the exact
  cut-off is a default.
- `deload-practice` — limited. Trained strength and physique athletes deload ~6 days every ~5–6 weeks, reducing
  volume and load and raising RIR, keeping frequency and exercises (Rogerson et al. 2024, Sports Med Open,
  survey, n = 246).
- `hrv-cycle-phase` — moderate. Vagally mediated HRV is lower in the luteal than the follicular phase (d ≈ −0.4),
  linked to progesterone (Schmalenberger et al. 2019, J Clin Med 8:1946, meta-analysis of 37 studies).
- `concurrent-training` — strong. No interference with hypertrophy or maximal strength; explosive strength can be
  blunted, more in the same session than with ≥ 3 h between (Schumann et al. 2022, Sports Med 52:601); strength
  first favours lower-body strength in combined sessions (Eddens et al. 2018, Sports Med 48:177).
- `recovery-time-course` — limited. Training to failure or with many reps per set prolongs the drop in mechanical
  performance to 24–48 h; stopping short of failure recovers within ~6–24 h (Morán-Navarro et al. 2017, Eur J
  Appl Physiol 117:2387; González-Badillo et al. 2016; Pareja-Blanco et al. 2020).
- `steps-health` — moderate. Mortality, cardiovascular disease, dementia and falls fall steeply up to ~5,000–7,000
  steps/day with smaller further gains (Ding et al. 2025, Lancet Public Health 10:e668).
- `wearable-sleep-stages` — limited. Consumer wrist devices agree fairly to moderately with polysomnography on
  stages (κ ≈ 0.2–0.5); display only (Schyvens et al. 2025, Sleep Advances 6(2):zpaf021).
- `composite-scores` — limited. Vendor readiness, energy and stress scores have no independent
  validation; context only.
- `wearable-vo2max` — moderate. Exercise-based watch estimates are acceptable at group level with wide individual
  error (Molina-García et al. 2022, Sports Med 52:1577).

## 8. Suggested order of work

1. ACWR replacement (§3.1) — before anything calls `DeloadAdvisor` with a ratio.
2. HRV metric per baseline and luteal-phase note (§3.2, §2.4).
3. Effective-set cut-off and register entry (§3.3).
4. Wording changes and level adjustments (§3.4, §4), with localisation.
5. "Measured / estimated / computed" labels on Today (§5).
6. Further reading (ADR-0030), starting with the "agrees" rows of §6 after reading each article.

## References (new or updated in this review)

- Pelland JC, Remmert JF, Robinson ZP, Hinson SR, Zourdos MC. The resistance training dose response:
  meta-regressions exploring the effects of weekly volume and frequency on muscle hypertrophy and strength gains.
  Sports Med 2026;56(2):481–505.
- Robinson ZP et al. Exploring the dose–response relationship between estimated resistance training proximity to
  failure, strength gain, and muscle hypertrophy: a series of meta-regressions. Sports Med 2024;54(9).
- Refalo MC et al. Influence of resistance training proximity-to-failure on skeletal muscle hypertrophy: a
  systematic review with meta-analysis. Sports Med 2023;53(3).
- Refalo MC et al. Similar muscle hypertrophy following eight weeks of resistance training to momentary muscular
  failure or with repetitions-in-reserve in resistance-trained individuals. J Sports Sci 2024.
- Rogerson D et al. Deloading practices in strength and physique sports: a cross-sectional survey. Sports Med Open
  2024.
- Lolli L et al. Mathematical coupling causes spurious correlation within the conventional acute-to-chronic
  workload ratio calculations. Br J Sports Med 2019;53:921.
- Impellizzeri FM et al. Acute:chronic workload ratio: conceptual issues and fundamental pitfalls. Int J Sports
  Physiol Perform 2020; and What role do chronic workloads play in the acute to chronic workload ratio? Time to
  dismiss ACWR and its underlying theory. Sports Med 2021;51:581–592.
- Schumann M et al. Compatibility of concurrent aerobic and strength training for skeletal muscle size and
  function: an updated systematic review and meta-analysis. Sports Med 2022;52:601–612.
- Eddens L et al. The role of intra-session exercise sequence in the interference effect. Sports Med 2018;48:177.
- Schmalenberger KM et al. A systematic review and meta-analysis of within-person changes in cardiac vagal
  activity across the menstrual cycle. J Clin Med 2019;8:1946.
- Morán-Navarro R et al. Time course of recovery following resistance training leading or not to failure. Eur J
  Appl Physiol 2017;117:2387–2399.
- Ding D et al. Daily steps and health outcomes in adults: a systematic review and dose-response meta-analysis.
  Lancet Public Health 2025;10:e668–e681.
- Schyvens AM et al. A performance validation of six commercial wrist-worn wearable sleep-tracking devices for
  sleep stage scoring compared to polysomnography. Sleep Adv 2025;6(2):zpaf021.
- Molina-García P et al. Validity of estimating the maximal oxygen consumption by consumer wearables: a systematic
  review with meta-analysis and expert statement of the INTERLIVE network. Sports Med 2022;52:1577–1597.
- Dewig HG et al. (2024) Are wearable photoplethysmogram-based heart rate variability measures equivalent to
  electrocardiogram? A simulation study. Sports Med.
