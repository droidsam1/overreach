# 0048 — Training load, immunity, allergy symptoms and soreness

- **Status:** Proposed
- **Date:** 2026-11-28

## Context

An athlete running 4 km sessions and lifting twice a week reported lingering leg soreness and asked whether
combined running and strength load can raise the risk of colds or allergy-like symptoms, and what dosing,
weekly structure, supplements or recovery habits help. Overreach has `illness-return` (what to do once ill),
`readiness-sleep`, `weekly-load-change` and the hybrid leg-and-run rules, but nothing on whether load itself
predisposes to illness. This ADR records the evidence and decides what the app does with it. It is not a medical
device and never diagnoses (see [AGENTS.md](../../AGENTS.md)).

### What the evidence says

1. **"Open window" is contested.** The idea that hard exercise leaves hours of immunosuppression is poorly
   supported. Post-exercise drops of blood immune cells fit redistribution to tissues better than suppression;
   salivary IgA and lymphocyte changes do not reliably predict infection. Campbell and Turner 2018, *Front Immunol*
   9:648 (narrative review; parts of the field disagree).
2. **Where a signal exists, it is at high load.** Narrative reviews and observational data link more
   upper-respiratory symptoms to marathon and ultra events, heavy training blocks and congested calendars. Team-sport
   reviews mostly use salivary IgA as a surrogate. A "J-shaped" load–risk curve is a hypothesis, not a finding.
   Nothing found shows that 4 km runs plus two or three lifting sessions a week raise infection risk, and nothing
   found studies moderate resistance training for this outcome.
3. **Named risk factors.** The IOC consensus lists sudden load increases, congested calendars, psychological
   stress, travel, poor sleep and inadequate nutrition (Schwellnus et al. 2016, *Br J Sports Med* 50:1043; Walsh et
   al. 2011, *Exerc Immunol Rev* 17:64; low energy availability, Walsh 2019). This is a consensus, not a validated
   predictor, and thresholds for illness are not established (ACWR thresholds concern injury and are disputed; see
   `weekly-load-change`).
4. **Sleep.** In 164 adults exposed to rhinovirus, shorter actigraphy-measured sleep (under about 6–7 h) went with
   more clinical colds; sleep fragmentation and diaries did not (Prather et al. 2015, *Sleep* 38:1353). General
   adults, not athletes. The "four times" figure comes from press coverage.
5. **Supplements.**
   - *Carbohydrate during prolonged exercise* (≥ 30 g/h, sessions of about 90 min or more) blunts cortisol and
     leucocyte rises (Christ et al. 2024, systematic review, *Front Sports Act Living*; Henson/Nieman 1999;
     Davison and Gleeson 2005). It does not apply to 40–60 min sessions. Pre-exercise carbohydrate alone does little.
   - *Glutamine:* a few small, old trials in endurance athletes report fewer self-reported infections (Castell et al.
     1996); the Walsh 2011 position statement does not recommend it (read in a later reproduction of its table, not
     in full text). No evidence for fasted dosing the day after a run.
   - *Vitamin C/E, multivitamins, fish oil, β-glucan:* not recommended in the same statement.
   - *Vitamin D:* benefit in insufficient athletes training in winter in one RCT, no effect on sIgA or symptom
     duration in a small meta-analysis. Measure before supplementing.
   - *Probiotics:* mixed; some meta-analyses show lower symptom severity, others no change in illness days.
6. **Allergy.** Allergic rhinitis is common in athletes (one survey of 636: 42.6 % reported pollen allergy, over 80 %
   of those reported impaired performance, most undertreated). No trial found that exercise worsens or improves it.
   Regular intranasal corticosteroid started before the season, morning or post-rain sessions and treatment of
   triggers are expert advice, not tested interventions. Many "colds" in athletes are not infections (own recollection
   of Spence et al. 2007; not re-checked here).
7. **Soreness.** DOMS after eccentric work usually peaks 24–72 h and fades by about 72 h (practitioner sources).
   Unaccustomed running and downhill running damage muscle, and the repeated-bout effect protects regular runners
   (`run-before-strength-carryover`). Lifting can impair later running for several days, with rules of thumb of
   48–72 h before a hard run after heavy lower-body work (Doma et al.; practitioner articles, not controlled
   thresholds). Soreness beyond 72 h, or worsening after day 3, suggests too much.
8. **What the soreness case showed.** The soreness came 48 h after a leg session of unilateral squats, front squats
   and hinges (18 sets), five days after an easy run. It matched the lifting session's timing, not the run, and
   not "total load".

## Decision

1. **No rule claims load causes illness.** Evidence is limited and the athlete's load is far below the studied range.
   Record it as `exercise-immune-load` (limited, no rule) in the evidence register.
2. **No supplement recommendations in the app.** The Assistant and reports do not suggest glutamine, vitamins C/E or
   probiotics. Vitamin D and allergy treatment are for a clinician.
3. **Soreness is attributed to the session that matches its timing.** Today's copy and the Assistant report show the
   last heavy lower-body session and the time since it, instead of blaming the week's total.
4. **Illness-risk context is soft and opt-in.** A single combined cue is allowed when three things coincide: a
   week-load spike (`weekly-load-change`), short sleep (`readiness-sleep`) and a rise in resting HR or a stress report.
   It says "sleep and ease the next hard session", never "you are about to get ill".
5. **Respiration rate, SpO₂ and wrist temperature** stay display-only until a device-specific validation exists
   (`composite-scores`, evidence review 2026-11).
6. **Allergy** is a free-text/check-in context item, not a rule. Symptoms above the neck with no fever follow the
   existing symptom guidance in `illness-return` and the clinical review already planned.

## Practical guidance (reference for copy and the Assistant)

Ranked by support. These are general suggestions, not a prescription.

1. Sleep about 7 h or more; protect it in heavier weeks.
2. Change one thing per week. Avoid raising leg volume and run volume together, and avoid a sudden jump.
3. Eat enough energy; avoid chronic deficit.
4. Carbohydrate during sessions of about 90 min or more, not for short sessions.
5. Space runs from heavy leg sessions: easy run after, hard run after about 48–72 h (heuristic).
6. Use easy walking for soreness (`walking-active-recovery`).
7. Allergy: treat triggers, intranasal steroid before the season, morning or post-rain sessions.
8. Check vitamin D in winter if unsure; skip glutamine and megadoses of antioxidants.
9. Hand hygiene and avoiding sick contacts matter as much as training dose.

## Consequences

- New evidence entry in [evidence.md](../evidence.md#exercise-immune-load--limited-no-rule). No code changes now.
- Candidate work, each with its own issue if accepted:
  1. *Soreness attribution:* show "last heavy leg session N days ago" in Today and the report. Cheap, uses existing
     `LowerBodyLoad` and check-in soreness. Highest value.
  2. *Soreness persistence cue:* check-in soreness 2–3 on day 3+ after a heavy leg session suggests an easier day
     (aligns with the 72 h marker).
  3. *Combined load, sleep and resting-HR cue* (decision 4). Needs thresholds replayed on real histories before
     release (as ADR-0047).
  4. *Sleep summary in the weekly review:* nights under 6 h, with the 7 h guidance and the Prather caveat.
  5. *Assistant context:* include days since the last heavy leg session and run in the shared report.
  6. *Allergy context:* an optional check-in flag so the Assistant stops interpreting nasal symptoms as illness.
  7. *Illness hints from respiration rate or temperature:* later, after validation.
- Not implemented: supplement advice, glutamine timing, any immune-risk score.

## Limits of this research

Mostly narrative reviews, small trials and practitioner sources; full texts were not read for several items (flagged
above). Revisit if a meta-analysis of resistance or hybrid training and URTI appears.
