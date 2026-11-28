# 0049 — Stress, recovery and a short check-in that explains the numbers

- **Status:** Accepted
- **Date:** 2026-11-28

## Context

The athlete asked whether resting HR, HRV and sleep can show stress and poor recovery, and whether a short set of
clinical questions (stress, anxiety, soreness, joint pain) would let Overreach cross the data and give more precise
advice on load and recovery. The check-in has energy (1–5), soreness (0–3), a note, an illness flag and one
contextual yes/no question. Stress is yes/no and weighs zero in the readiness light; no stress is inferred from the
device ([ADR-0038](0038-life-stress-in-deload-proposals.md)).

### Evidence

1. **Self-report beats single objective markers.** Subjective well-being reflects acute and chronic load more
   sensitively and consistently than common objective measures, and the two often disagree (Saw, Main and Gastin
   2016, *Br J Sports Med* 50:281; 56 studies). Already `readiness-subjective`.
2. **No single marker.** The ECSS/ACSM consensus treats overtraining as a diagnosis of exclusion; markers such as
   HRV and resting HR do not meet criteria for general use (Meeusen et al. 2013). Resting HRV and HR change little in
   functional overreaching and weekly vagal HRV can rise (Bellenger 2016; Manresa-Rocamora 2021). A low-HRV rule misses
   part of overreaching. Already `deload-recovery-signals`.
3. **Stress is not readable from HRV, resting HR or sleep.** They move with training, illness, heat, cycle phase,
   alcohol and sleep loss. Alcohol raises nocturnal resting HR by about 3 bpm (63.6 to 66.6 bpm in one smartwatch
   study; *Nutrients* 2025) and lowers HRV in a dose-dependent way in about 21,000 wearable users (*PLOS Digit Health*
   2026). Garmin stress and Body Battery are unvalidated proprietary scores. Late meals and caffeine: no reliable
   source found.
4. **Stress, sleep and injury.** The stress response is associated with injury (r ≈ 0.27, heterogeneous; Ivarsson
   et al. 2017, *Sports Med*); sleep under 7 h and distress in the 7 days before injury are associated with more
   injury (2024 consensus, *Sports Med* 54). Small effects, observational.
5. **Recovery framing.** Recovery is the balance between stress (training and life) and restoration; insufficient
   recovery is not the same as non-functional overreaching (Kellmann et al. 2018; read from an extract).
6. **Brief wellness questionnaires.** Soreness, fatigue, sleep quality, stress and mood are the usual domains
   (Hooper-style, 4–5 items). Custom short scales are common but lack strong validation, and shortening can cost
   validity. No validation against non-functional overreaching found.
7. **Anxiety screening.** GAD-2 (cut-off 3) screens for generalised anxiety in clinical settings; it is not validated
   as a daily athlete monitoring item, and scoring it would make a clinical claim. No athlete-specific evidence found.
8. **Pain.** No validated cut-off separates DOMS from injury pain on a 0–10 scale. Experimental DOMS peaks at 24–48 h
   and resolves within 5–7 days; pain that is focal to a joint or tendon, rising or lasting over a week deserves
   clinical review. A 2024 Delphi on athlete pain assessment was not confirmed.
9. **HRV-guided training** has a clear effect on HRV and a small, non-significant one on performance (2021
   meta-analyses); no 2024 meta-analysis found.

## Decision

1. **Biometrics trigger questions; answers decide.** HRV, resting HR and sleep stay corroborating signals. The
   subjective answer explains and, where the rules already say so, drives the advice (as `readiness-combination`).
2. **Ask for the cause when a signal deviates.** One tap: alcohol, late or heavy meal, heat, travel, poor night, none.
   An attributed day stays visible but does not add to the recovery-signal count of the deload rule.
3. **Add two optional one-tap items to the daily check-in:** stress or tension (1–5) and sleep quality (1–5). Stress
   4–5 counts as "yes" for ADR-0038; stress keeps zero weight in the readiness colour. Show the 14-day trend once
   there are at least 5 answers.
4. **Ask about soreness only when it matters.** With soreness 2 or more: zone and type (muscle ache, joint, tendon,
   sharp). For joint or tendon pain: worse than yesterday, limits movement. Worsening, limiting or over 7 days →
   change the exercise and see a clinician. Never diagnose. Pain wording waits for the pending clinical review.
5. **No anxiety or depression scoring.** No GAD-2 or PHQ-2 in the daily flow. A weekly optional module needs clinical
   review and its own ADR.
6. **No stress inferred from the device**, no Garmin stress or Body Battery, no illness-risk score.
7. **Cross-reading patterns** (reference for copy and rules, each a heuristic):
   - deviating biometrics + declared cause → attribute to the cause, no load penalty;
   - deviating biometrics + poor sleep and low energy, no cause → likely under-recovery, ease intensity;
   - normal biometrics + high stress + low energy → life stress, ADR-0038 steadier week, protect sleep;
   - diffuse soreness 24–72 h after heavy leg work → expected, easy movement, no hard run (ADR-0048);
   - focal joint or tendon pain, worsening or over 7 days → modify and seek clinical advice;
   - high HRV + low energy + falling performance → possible non-functional overreaching; use the performance trend,
     not HRV alone.
8. **Validate before widening.** Replay the new items against real histories before they carry weight, as in
   [ADR-0047](0047-muscle-balance-alerts.md).

## Consequences

- Optional fields on `CheckIn` (stress, sleep quality, deviation cause, soreness zone and type, pain follow-ups) with
  tolerant decoding and backup tests (ADR-0004/0018). The check-in stays about 10 seconds; extra questions are
  conditional.
- Issues: [#414](https://github.com/droidsam1/overreach/issues/414) deviation cause,
  [#415](https://github.com/droidsam1/overreach/issues/415) soreness zone/type and joint-pain block,
  [#416](https://github.com/droidsam1/overreach/issues/416) stress and sleep quality.
- Evidence entries `recovery-stress-inference` and `check-in-brief-questions` in
  [evidence.md](../evidence.md#recovery-stress-inference--limited-no-stress-rule).

## Limits of this research

Kellmann, Meeusen and the stress-injury consensus were read from extracts; no validation study of a brief
questionnaire against non-functional overreaching, the Hooper index, the Perceived Stress Scale, caffeine or late-meal
effects, or athlete GAD-2 use was found.
