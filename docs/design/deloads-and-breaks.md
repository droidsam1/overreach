# Deloads, breaks and stalled lifts

Status: planned (reviewed 2026-11-21). Rules: [progression engine](progression-engine.md#deload-proposals),
ADR-0027 and ADR-0029. Evidence keys: `deload-design`, `deload-cost`, `deload-practice`, `deload-recovery-signals`,
`unplanned-deload`, `stall-heuristics` in [the evidence register](../evidence.md).

## Continue from here

Take the first task below whose boxes are not all checked. Each task is one pull request. Task 1 is done by
[training services task 2](training-services.md#2-recovery-status); build tasks 2–6 on `TrainingServices` once it
exists. Tasks 1 and 2 fix wrong advice and come first; tasks 5 and 6 change the Today card that
[#94](https://github.com/droidsam1/overreach/issues/94) then places in the page. Record checks that need an iPhone
in [#21](https://github.com/droidsam1/overreach/issues/21).

## What the athlete saw

Reported with screenshots on 2026-11-21 (Galician UI, hybrid athlete with Garmin):

- Today proposed a deload week with "11 main lifts have stalled", "51 weeks since your last deload" and "HRV below
  your usual range on 7 of the last 7 days", each followed by an evidence label, then the deload plan, then every
  exercise of the next session with last time and deload targets. The readiness header above it said "4 of 7
  comparable readings were low".
- Plan said "Last deload 2 weeks ago" and, below it, asked about three periods from September and October
  ("Count this period as a deload?") that the athlete no longer remembers.

The athlete could not tell why a deload was proposed two weeks after one, which lifts stalled and since when, what
to do about a stalled lift, or what evidence supports the proposal.

## Causes found in the code

1. **Two answers for "last deload".** `DeloadAdvice.make` (TodayPresentation) passes
   `profile.deloads.last?.start` and the confirmed detected periods to `DeloadAdvisor.proposal`. `PlanAnalysis.run`
   uses the *end* of the latest planned deload and the latest confirmed period. Their inputs also differ: Today
   reads runs from every source (`TodayModel.readRecentRuns`, a failing source sets `runReadFailed`), Plan only from
   sources that are available (`PlanModel.analyse`). With `runReadFailed`, or a hybrid goal and no runs,
   `DeloadDetection` marks every period `needsConfirmation`, so none counts. Without any recovery, the interval
   signal counts from the first session in the 365-day window: "51 weeks".
2. **Stale and mislabelled stalls.** `StallDetection.status` compares the last 3 exposures with the 6 before,
   whatever their dates, so a lift dropped months ago stays stalled. `DeloadAdvisor` falls back to every lift when
   none is marked main (`ProgressionSettings.isMainLift` defaults to false) but the text says "main lifts".
3. **A deload from stalls and a timer alone.** Stalls (2 points) plus the 6-week interval (1 point) reach the
   threshold of 3, so a proposal needs no sign of fatigue. Stalls without fatigue usually call for a change to that
   lift (`StallSuggestion` already lists them), not a week of reduced training for everything.
4. **One break for both disciplines.** `DeloadDetection` returns one list of periods for the athlete; a week
   without lifting but with runs is not a strength break. Every ambiguous period of the last year waits for an
   answer in Plan.
5. **Two meanings of "HRV low".** Readiness counts readings below the range; `RecoveryTrend.hrvLowDays` counts days
   whose 7-day trend was below it. Both are shown as "HRV below your usual range".
6. **Everything at once.** The deload card shows every reason with its evidence label, the plan and the whole
   session preview inline (`TodayView.deload`).

## Evidence for breaks

| Finding | Source | Use |
| --- | --- | --- |
| A deload is reduced training to manage fatigue, not stopping. | Bell et al. 2023, Sports Med Open 9:87 (Delphi) | Definition (`deload-design`). |
| Stopping resistance training lowers strength with a dose-response on duration; trained young adults lose little in the first weeks. | Bosquet et al. 2013, Scand J Med Sci Sports 23:e140 (meta-analysis) | A 1–2 week strength break is recovery, not lost progress. |
| Three-week breaks every six weeks gave hypertrophy similar to continuous training over 24 weeks (untrained men). | Ogasawara et al. 2013, Eur J Appl Physiol 113:975 | Same. |
| A 1-week break mid-programme slightly reduced lower-body strength gains; hypertrophy unchanged. | Coleman et al. 2024, PeerJ 12:e16777 (RCT) | Breaks are not proposed; past ones still count as recovery (`deload-cost`). |
| In trained endurance athletes VO2max and blood volume fall within the first weeks without training. | Mujika & Padilla 2000, Sports Med 30:79 (review) | Running breaks beyond about 2 weeks call for an easy return, not a deload. |

No study tests deloads or breaks in concurrent training. Treating strength and running breaks separately, and the
7-day and 14-day limits below, are product heuristics. Task 3 records them as a new evidence entry.

## Implementation backlog

### 1. One "last recovery" for Today and Plan

Shipped through [training services](training-services.md) tasks 1 and 2 (`SourceReader`, `RecoveryHistory`).

- [x] A pure function in `Analytics` (`RecoveryHistory.lastRecovery`) returns the last recovery before a day: its
  last day and kind. Discipline comes with task 3.
- [x] `DeloadAdvisor.proposal`, `DeloadAdvice.unconfirmedBreak`, `PlanAnalysis.run` and `WorkoutModel` use it.
- [x] Today and Plan read runs through `SourceReader`.
- [x] Without any recovery: "No deload or break in the 8 weeks of training logged."
- [x] Tests: Today and Plan count from the same deload; an accepted deload gives no interval signal in Today.

Finish line: with the same data, Today and Plan never disagree about the last deload.

### 2. Count only lifts in current training, and say which

- [x] Require an exposure in the last 28 days (`DeloadAdvisor.Settings.lookbackDays`) for lift signals.
- [ ] When a rotation or routine exists (`SessionRotation`, ADR-0033), count only its exercises.
- [x] Say "main lifts" when lifts are marked main and "lifts you train now" otherwise.
- [ ] Add `StallDetection` output that explains a stall: exercise, the date progress stopped (first exposure of the
  flat window), best estimated 1RM and the set behind it, last exposure, and the `StallSuggestion`s.
- [ ] Rule change: a deload proposal needs at least one fatigue signal (performance drop, RPE creep, weekly load
  spike or a sustained recovery signal). Stalls and the interval reinforce it. Stalls alone produce per-lift
  suggestions (task 6) instead. Record the change in a new ADR (next free number) and update `stall-heuristics`,
  `deload-design` and [progression engine](progression-engine.md#deload-proposals).
- [x] Tests: a stale lift is excluded from current stalls in Today, Plan, Workout and the AI context.
- [ ] Tests: three stalled current lifts with no fatigue signal give no proposal. Adding RPE creep gives one.

Finish line: every stalled lift Overreach mentions is one the athlete trains now, and Today can name it.

### 3. Breaks per discipline, counted automatically

Rules (heuristics, configurable in `DeloadDetection`):

- At least 7 complete days without strength work (logged sessions or watch recordings) is a **strength break**.
- At least 7 complete days without runs is a **running break**, for athletes who run: a running goal, or runs in at
  least 2 of the 4 weeks before.
- A break counts as recovery for its discipline only. The strength deload advice reads strength recovery; running
  advice may read running recovery.
- A strength break of 14 days or more is a **return**: no deload proposal until 4 weeks of training after it, and
  performance signals compare only sessions after it (already the case for drops). A running break of 14 days or
  more makes the next runs easy (`EasyRunAdvisor`).

Work:

- [ ] Add `discipline` (strength, running) to `DetectedDeload`; detect gaps per discipline. Reduced-load weeks stay
  ambiguous and keep asking (task 4).
- [ ] Add a profile setting, e.g. `AthleteProfile.countsBreaksAutomatically`, decoded with a default so older
  backups load (ADR-0018). Default on. When on, every gap that meets the rules counts without asking, over all
  imported and logged history. When off, today's behaviour.
- [ ] Settings → Training: a toggle "Count breaks as rest automatically" with one line of explanation. Logic and
  texts in a presentation model (ADR-0014); strings in en, es and gl (ADR-0015).
- [ ] Old `DeloadDecision`s, which have no discipline, keep applying to both.
- [ ] Add the `training-breaks` evidence entry from the table above, and an ADR that extends ADR-0029.
- [ ] Tests: a week of runs and no lifting is a strength break only; with the setting off it asks as before; a
  20-day gap gives a return and no deload proposal.

Finish line: with the setting on, a week without lifting counts as strength recovery without any question.

### 4. Ask about the latest periods only

- [ ] Plan asks only about ambiguous periods after the last recovery (task 1), at most the two newest, and none older
  than 12 weeks. Older ones are not asked and do not count; keep them behind an "Older periods" link for anyone who
  wants to answer.
- [ ] Each question shows what was logged, so the athlete can answer without remembering: "8–14 Oct: 2 strength
  sessions, about 40 % of your usual sets; no runs." Buttons: "Yes, it was rest" and "No".
- [ ] One line says why the app asks: the answer sets when the next deload is due.
- [ ] Today's "Did you already take a break?" uses the same selection.
- [ ] Tests: five ambiguous periods in a year give at most two questions, newest first.

Finish line: Plan never asks about a period older than 12 weeks unless the athlete opens the older list.

### 5. Today deload card: summary first, details on demand

- [ ] The card shows a title, one sentence with the main reason in plain words ("Your lifts stopped progressing and
  the same weights feel harder"), "Start deload week", "Not now" and "Why and what changes". No evidence labels, no
  session preview on the card.
- [ ] A detail screen with, in this order: **Why now** (training signals first, recovery signals marked as
  supporting; stalled lifts link to task 6), **Your last rest** (date and kind from task 1, linking to Plan's
  recovery history), **What changes** (the plan text and "See your deload session" with the current preview),
  **Evidence** (one plain sentence per evidence key, its level once, and `FurtherReading` links).
- [ ] Rename the trend signal so it differs from readiness: "Your 7-day HRV average stayed below your usual range on
  5 of the last 7 days."
- [ ] All texts come from `TodayPresentation`; the views only render (ADR-0014). Strings in en, es and gl.
- [ ] Tests on the model: the summary sentence for each signal combination, and that the detail lists every signal.

Finish line: the card fits in one screen on a compact iPhone at default text size, and every reason is one tap away.

### 6. Stalled lifts as their own recommendation

- [ ] Plan gets a **Lifts to unblock** section (hidden when empty): each row names the lift, "No progress since
  12 Sep (best 82.5 kg × 5)", and the first `StallSuggestion` in plain words with its evidence on the detail.
- [ ] Where a suggestion maps to a setting (microloading, double progression, rep range), offer "Apply" that changes
  that exercise's `ProgressionSettings` after confirmation; other suggestions are advice only.
- [ ] Today shows stalls only through the deload detail (task 5) or, with no deload proposed, one line "2 lifts
  stopped progressing" linking to the section.
- [ ] Tests: rows, dates and suggestions for a stalled lift; nothing for a lift not trained in 28 days.

Finish line: for each stalled lift the athlete sees since when and one concrete next step.
