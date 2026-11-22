# Daily recommendations and hybrid planning

Updated 2026-11-20

Today should tell the athlete what to do, which signals matter, and how the suggestion changes the session they intended to do. Hybrid plans should also represent what the athlete wants from running and how it ranks alongside strength work. The [evidence review](../evidence-readiness-and-hybrid.md) records which findings can inform these decisions and which choices need validation as product heuristics.

## Continue from here

Use [Priorities](../priorities.md) to choose the next implementation. [Task 3](#3-ask-a-question-that-changes-the-decision)
has an implemented check-in flow with a pending clinical review before release.

## Shipped baseline

- Today has an explainable readiness card and a contextual check-in. The seven-day training and recovery timeline now only feeds the readiness explanation; Today no longer lists it ([ADR-0033](../adr/0033-next-session-from-rotation.md)). `MetricsSource` and `WorkoutRepository` supply the timeline, with `RunDeduplication` and `StrengthActivityMatching` for mirrored workouts. [Timeline PR](https://github.com/droidsam1/overreach/pull/75) · [Explanation PR](https://github.com/droidsam1/overreach/pull/78)
- The readiness result lists every input with its source, status (compared, missing, stale, out of range, building baseline), recent coverage, reference window and outcome. Sleep and daytime HRV readings are separate series, and implausible readings are ignored and counted. [Input audit ADR](../adr/0032-auditable-readiness-inputs.md)
- Plan assigns routines and strength rest days to dates next to runs, and Today compares the assigned routine with a lighter option on amber days. [Dated strength PR](https://github.com/droidsam1/overreach/pull/99)
- Plan stores hybrid running goals, dated runs, races and rest days. A planned run can link explicitly to an imported recording. Today uses recovery, recent runs and the calendar for easy-run advice. Strength currently uses an undated rotation and an optional amber example. [Strength PR](https://github.com/droidsam1/overreach/pull/79) · [Running goal PR](https://github.com/droidsam1/overreach/pull/89) · [Calendar PR](https://github.com/droidsam1/overreach/pull/95)

## What Today should show

Lead with an action, then show the strongest observations and any missing context that affects the decision. Expand **Why this suggestion?** for the series used, dates and coverage, baseline comparison, relevant training and races, and source links near the claim they support. Give the evidence for using a signal and the confidence in today's interpretation their own wording. A research result about HRV-guided endurance training does not establish the cause of an individual reading or validate a specific change to today's routine.

Example in Galician using the screenshot. The valid-night count and today's plan have to come from app data before filling the placeholders.

> **Se te atopas ben, fai a sesión de hoxe máis suave.** A túa VFC leva varios días por debaixo do habitual. Houbo 4 noites baixas entre as {n} noites con datos comparables nos últimos 7 días. O pulso en repouso de hoxe é de 60 lpm, fronte aos 59 de media esta semana. Durmiches 7,6 h.
>
> **Tes algún síntoma novo ou notas máis estrés do habitual?**

The 37 ms and 59 bpm in the screenshot are weekly averages. A personal normal range requires the longer reference window. The screenshot does not establish whether 7.6 hours is usual, whether 4 of 7 nights were actually measured, or whether there was a hard session beforehand. Only show a sentence such as “A baixada comezou despois das series do martes” when timestamps and coverage support that ordering. A temporal match can make recent exertion a plausible contributor.

| Day and intent | Example output when easy exercise is appropriate |
| --- | --- |
| Intervals scheduled today | “Tiñas 6 × 800 m. Cambia as series por 25 min de trote a un ritmo ao que poidas falar en frases completas.” Offer a separate move-session action that checks nearby hard days. |
| Strength scheduled today | “Tiñas 4 × 6 de sentadilla. Fai 2 × 6 cun peso co que poderías facer polo menos 4 repeticións máis.” Use the actual routine and recent comparable work to show load when supported. |
| No session today, athlete taps **I want to train** | “O seguinte son series o xoves. Se queres correr hoxe, fai 20 min de trote cómodo.” If the next item is a race, preserve its preparation and offer only a compatible optional session. |
| Explicit rest or no useful plan | Identify planned rest explicitly. If an optional session fits, use a familiar easy option based on history and the athlete's chosen modality. With sparse history, offer an effort cue and let the athlete choose duration within familiar limits. |
| Race today, or safety-relevant symptoms | Show a separate race decision. With symptoms that change exercise safety, prioritize the symptom pathway and suppress easy-training suggestions where appropriate. |

The numbers above are examples for fixtures and copy review. Eligibility, actual duration, sets and effort must come from validated rules, recent exposure and the priority of adjacent sessions.

## Implementation backlog

Each task includes the portions already shipped and criteria for the remaining work. Start from the current delivery above.

### 1. Make the readiness inputs auditable

Coverage counts and missing-data reasons shipped in [#73](https://github.com/droidsam1/overreach/pull/73). Separate HRV series shipped in [#84](https://github.com/droidsam1/overreach/pull/84). Per-signal provenance, measurement protocol, plausible ranges, baseline overlap and the coverage of every input shipped with [ADR-0032](../adr/0032-auditable-readiness-inputs.md). The baseline keeps the nights it shares with the trend window and records how many. Device identity within Apple Health is not available.

- [x] Extend the readiness result with per-signal provenance, coverage, recency, measured values, reference window and comparison outcome. Keep device, statistic and measurement protocol comparable. Distinguish missing, stale and out-of-range data. Evaluate baseline overlap with the recent window and record the chosen policy. Keep the seven-day display summary distinct from the long-term baseline. [HRV series](../adr/0025-hrv-one-series-per-metric.md)
- **Done when** fixtures cover Garmin RMSSD and Apple SDNN together, sparse or invalid samples, a device switch, daytime fallback, a source outage and no data today. The low-night count always uses the eligible measured denominator and can explain why HRV was skipped. Old caches and backups decode or follow the documented rebuild path.

### 2. Join recovery with completed training

The first delivery ([#75](https://github.com/droidsam1/overreach/pull/75)) groups seven days of completed runs, strength workouts,
recovery and check-ins by local date. [ADR-0034](../adr/0034-reading-timing-and-race-tags.md) orders workouts by
the night behind each sleep reading, tags runs the athlete linked to a planned race, and compares the closest
comparable readings before and after the latest race. Within-person patterns across repeated bouts remain open.

- [x] After task 1, build a calendar-aligned timeline from metrics, check-ins, logged/imported strength and runs. Reuse History's source-matching behavior where applicable so mirrored workouts are counted once. Capture local start/end timing, run time/distance/effort where available and leg work from known muscle mappings and recorded sets/effort. Represent unclassified activities explicitly and allow confirmed race tags. Keep planned sessions out of completed load.
- **Done when** fixtures cover duplicate exports, indoor runs, missing RPE, overnight/time-zone boundaries, an actual race before a dip, a dip before a race and an empty training history. Show simple before/after comparisons first. A later within-person pattern requires repeated comparable bouts, lag and sample counts, and an uncertainty estimate. Evaluate confounders and sparse data before adding correlation coefficients. Avoid injury thresholds from coupled ACWR and avoid adding incomparable load units.

### 3. Ask a question that changes the decision

The first delivery ([#76](https://github.com/droidsam1/overreach/pull/76)) asked about unusual stress or new
symptoms. Today now uses audited input comparisons and recent linked running pain to select a prompt.
An athlete can report warning symptoms from any check-in and edit the answer later.

- [x] Extend the local check-in to distinguish new symptoms, fatigue, local running pain, muscle soreness, unusual stress and uncertainty. Ask one optional question and recompute after save or correction.
- [ ] Obtain clinical review of the symptom wording, escalation and return guidance before release. Start with [`illness-return`](../evidence.md#illness-return--limited) and the [IOC consensus](https://doi.org/10.1136/bjsports-2022-105759).
- **Decision examples.** With a low trend, elevated resting HR and ambiguous context, ask about new symptoms first. With an otherwise stable pattern and no recorded unusual training, ask whether life stress or another recent change might explain how the athlete feels. With local pain after running, ask whether it worsened or affected their stride. Fever or symptoms such as chest discomfort, unusual breathlessness or dizziness need the appropriate rest or care pathway. Determine the exact wording and escalation with clinical review. Keep unrelated questions out of the daily flow.
- **Done when** an isolated low trend can prompt a question, reported stress can add context, reported illness or exercise-limiting symptoms can change the action, and skipped answers preserve uncertainty. An old check-in never silently answers for today. No illness or stress classification comes from wearable readings alone. Test backup round-trips and keep new health context local unless explicitly shared.

### 4. Ship the explanatory card in Today

Today leads with an action and up to two observations that support it. The HRV summary uses the count of
eligible readings. **Why this recommendation?** explains the signals, shows baseline comparisons and missing
context, and links research beside the claim it supports. **Data sources and coverage** shows which readings
the rule compared. The shared report uses the same rule result and research links under its existing privacy rules.

- [x] Present the leading observations and supporting detail with en, es and gl copy. Use the measured
  HRV denominator and show stable or unavailable measurements when the checks support it.
- [ ] Verify large text and VoiceOver on an iPhone. Use the [repeatable usability check](iphone-ux.md#repeatable-beforeafter-check)
  and record the results in [#21](https://github.com/droidsam1/overreach/issues/21).

### 5. Compare against today's strength session and offer an optional alternative

The initial light example shipped in [#79](https://github.com/droidsam1/overreach/pull/79). A dated routine and
strength rest days shipped in [#99](https://github.com/droidsam1/overreach/pull/99).

- [x] On amber days, compare a dated routine's progression target with lighter sets, reps and effort. Show a
  starting weight when recent easy sets support it. Keep the comparison available alongside a scheduled run.
- [x] With no strength session due, offer **I want to lift today**. Use the next undated routine, the athlete's
  rotation or a familiar recent session as a reference. The example never starts a workout or advances the rotation.
- [x] Suppress the example on strength rest days, after strength work recorded today and when readiness advises
  skipping training. A race due today suppresses an optional lift.

Applying or moving a dated session belongs to the calendar and adjustment flows in tasks 7 and 8.

### 6. Add a running objective to hybrid goals

[#89](https://github.com/droidsam1/overreach/pull/89) adds an editable running distance, optional time and pain-free
criterion to hybrid goals. Optional goal fields round-trip through backup and appear in the context export. Plan
shows progress from explicitly linked recordings and lets the athlete report pain during and after each run.
Confirmation requires one linked run to satisfy every selected criterion. A timed goal uses the recorded total
duration. A pain-free goal requires a clear response for both periods. An older link without measured distance can
still carry a pain report. The running and strength priority control shipped; task 8 covers using it in recommendations.

- [x] Can start independently. Extend `TrainingGoal` with optional distance, completion/time target, symptom-free criterion, optional target event/date and running/strength priority. Allow completion plus symptom-free and time plus symptom-free where desired. Add edit and progress surfaces in Plan and an optional onboarding path. Preserve priority lifts. Use recent performance or a recent tolerated run to ground progress and show uncertainty for ambitious targets.
- **Done when** “finish 5 km”, “run 5 km without pain” and “5 km in 15 min” round-trip in app storage, backup and the relevant versioned plan/context exchange. The last example displays a goal pace of 3:00/km and uses current performance to set training intensity. A pain-free goal tracks athlete-reported symptoms during and after runs and never promises a symptom-free outcome. Old hybrid profiles can continue with no running objective.

### 7. Represent planned runs, races and dates

[#89](https://github.com/droidsam1/overreach/pull/89) supports one manually entered next running day, including a
race or explicit rest. [#95](https://github.com/droidsam1/overreach/pull/95) adds the multi-day running calendar,
stable moves and explicit links to completed runs. The shared schedule includes dated strength alongside
structured running entries, with rest, the strength rotation and confirmed run links. [ADR-0040](../adr/0040-structured-running-schedule.md)
covers the prescription fields, race priority, moves and postponement. Applying proposed changes is task 8.

- [x] After task 6, add a shared schedule view that preserves the strength rotation. Include dated sessions/rest, undated next items, planned races with priority, completed/adjusted/postponed status and explicit or confirmed links to logged activity. For runs include purpose (easy, long, threshold, intervals, event), duration or distance, optional reps/recovery and an intensity basis (pace, HR zones or perceived effort).
- **Done when** two sessions can share a day, runs and races can be displayed or moved without losing identity, a missed run never implies a completed run, and import/export and restore cover old and new data under ADR-0017/0018. Document calendar and conflict semantics in an ADR before changing persistence.

### 8. Adjust planned runs and protect nearby sessions

[#89](https://github.com/droidsam1/overreach/pull/89) compares a saved session with a conversational run when
recovery signals and recent running support it. [#95](https://github.com/droidsam1/overreach/pull/95) extends the
checks to all running entries through tomorrow. Today distinguishes race day, keeps a running rest day and
uses discipline priority on strength/run days. A free-day option opens on request.

- [x] Compare planned runs with easy alternatives using recent duration and conversational effort. Review a
  same-day change in Plan before saving. Protect races, next-day quality runs and nearby scheduled strength.
  Rescheduling uses the regular calendar editor.
- **Done when** tests include hard intervals → easy, easy → shorter or unchanged, long run → a compatible alternative, race today, race soon, a strength/run double, explicit rest and no plan. Declining or skipping keeps the original schedule. Concrete example doses are configurable heuristics and never override the symptom pathway.

### 9. Research and validate hybrid planning rules before automating plans

- [ ] Start the research in parallel with tasks 1 and 6. Extend the [evidence review](../evidence-readiness-and-hybrid.md#review-protocol-for-future-rules) and add stable keys to `docs/evidence.md` as rules become implementable. Compare aerobic/strength priorities, acute fatigue, long-term adaptations and tissue-specific exposure. Build templates for completion, symptom-sensitive progression and time goals. Integrate only after tasks 6–8. Start from current training, available days, running volume and intensity distribution, strength priorities and target event. Support phases and taper where relevant, with explicit defaults when evidence does not resolve programming choices.
- **Done when** fixtures cover a new runner aiming to finish 5 km, a returning runner aiming to run pain-free, a competitive 5 km target, a lifter prioritizing strength, and a week with a race and two hard lower-body demands. Every proposed change explains the conflicting sessions and intended adaptation. Validate on historical replay and review with a running coach and a sports clinician before using symptom-sensitive or high-stakes prescriptions. Track missing-data behavior, unnecessary prompts, skipped suggestions and adverse recommendations in review fixtures.
