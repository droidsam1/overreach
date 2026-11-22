# Deloads, breaks and stalled lifts

Status: tasks 1–7 implemented, 8–10 open (reviewed 2026-11-21). Rules: [progression engine](progression-engine.md#deload-proposals),
ADR-0027 and ADR-0029. Evidence keys: `deload-design`, `deload-cost`, `deload-practice`, `deload-recovery-signals`,
`unplanned-deload`, `stall-heuristics` in [the evidence register](../evidence.md).

## Continue from here

Take the first task below whose boxes are not all checked. Each task is one pull request. Task 1 is done by
[training services task 2](training-services.md#2-recovery-status); build tasks 2–6 on `TrainingServices` once it
exists. All tasks are done. Task 5 explains the Today card that
[#94](https://github.com/droidsam1/overreach/issues/94) then places in the page. Task 6 supplies lift findings
(`LiftsToUnblock`, shown in Plan)
to [Recovery & Progress](https://github.com/droidsam1/overreach/issues/126). Record checks that need an iPhone
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

## Causes in the previous delivery

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
7-day and 14-day limits below, are product heuristics. See [training-breaks](../evidence.md#training-breaks--heuristic).

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
- [x] When a rotation or routine exists (`SessionRotation`, ADR-0033), count only its exercises.
- [x] Say "main lifts" when lifts are marked main and "lifts you train now" otherwise.
- [x] Add `StallDetection` output that explains a stall: exercise, the date progress stopped (first exposure of the
  flat window), best estimated 1RM and the set behind it, last exposure, and the `StallSuggestion`s.
- [x] Rule change: a deload proposal needs at least one fatigue signal (performance drop, RPE creep, weekly load
  spike or a sustained recovery signal). Stalls and the interval reinforce it. Stalls alone produce per-lift
  suggestions (task 6) instead. Record the change in [ADR-0036](../adr/0036-deload-needs-fatigue.md) and update `stall-heuristics`,
  `deload-design` and [progression engine](progression-engine.md#deload-proposals).
- [x] Tests: a stale lift is excluded from current stalls in Today, Plan, Workout and the AI context.
- [x] Tests: three stalled current lifts with no fatigue signal give no proposal. Adding RPE creep gives one.

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

Shipped in [ADR-0037](../adr/0037-training-breaks-by-discipline.md). Settings → Training controls automatic
counting. Progress in Recovery & Progress lists strength and running breaks. A strength break resets the deload interval.
Long breaks trigger a return period, and lower-load weeks remain available for review.

### 4. Ask about the latest periods only

- [x] Ask about the two newest unanswered periods that fall entirely within 12 weeks and start after the last
  strength recovery. Keep the other unanswered periods under **Older periods** in Progress.
- [x] Show the dates, recorded strength sessions and runs, and the share of usual weekly working sets when
  comparable set counts are available. Flag incomplete run data. Offer **Yes, it was rest** and **No**.
- [x] Explain how the answer affects deload timing or, for a running-only period, running recovery history.
- [x] Today and Plan use the same selection. Today asks about the latest strength candidate if the answer would
  change a proposed deload. Keep the **Older periods** entry when [#126](https://github.com/droidsam1/overreach/issues/126)
  moves recovery history.
- [x] Tests cover five ambiguous periods, the 12-week boundary, and a more recent recovery.

Finish line: the default flow asks about at most two recent periods, both within the last 12 weeks.

### 5. Today deload card: summary first, details on demand

- [x] The card shows a title, one sentence with the main reason in plain words ("Your lifts stopped progressing and
  the same weights feel harder"), "Start deload week", "Not now" and "Why and what changes". No evidence labels, no
  session preview on the card.
- [x] A detail screen with, in this order: **Why now** (training signals first, recovery signals marked as
  supporting), **Your last rest** (date and kind from task 1, linking to the recovery history),
  **What changes** (the plan text and "See your deload session" with the current preview),
  **Evidence** (one plain sentence per evidence key, its level once, and `FurtherReading` links).
- [x] Rename the trend signal so it differs from readiness: "Your 7-day HRV average stayed below your usual range on
  5 of the last 7 days."
- [x] All texts come from `TodayPresentation`; the views only render (ADR-0014). Strings in en, es and gl.
- [x] Tests on the model: the summary sentence for each signal combination, and that the detail lists every signal.

The card opens the explanation in one tap. Verify the fit on a compact iPhone at default text size in
[#21](https://github.com/droidsam1/overreach/issues/21).

### 6. Stalled lifts as their own recommendation

- [x] Prepare shared **Lifts to unblock** findings for the Progress detail in
  [#126](https://github.com/droidsam1/overreach/issues/126). Each row names the lift, "No progress since
  12 Sep (best 82.5 kg × 5)", and the first `StallSuggestion` in plain words with its evidence on the detail.
- [x] Where a suggestion maps to a setting (microloading, double progression, rep range), offer "Apply" that changes
  that exercise's `ProgressionSettings` after confirmation; other suggestions are advice only.
- [x] Tests: rows, dates and suggestions for a stalled lift; nothing for a lift not trained in 28 days.

Finish line: each current stalled lift has a start date and one concrete next step. Keep those findings
reachable in Plan until #126 moves them and adds links from the deload detail.

Delivered: `LiftsToUnblock.find` (Analytics) returns each current stalled lift with its stall start, best set and
suggestions; `PlanAnalysis.liftsToUnblock` feeds the block advice and Plan's **Lifts to unblock** section.
`StalledLift.applying` maps microloading, the switch to double progression and a new rep range to
`ProgressionSettings`. A routine's prescription keeps scheme changes in that routine. Microloading stops at 1 kg.

### 7. Ask about life stress before proposing a deload

An athlete two weeks after a deload, with stalled lifts and HRV a few points under their usual range, received
another deload proposal that stress could explain ([ADR-0038](../adr/0038-life-stress-in-deload-proposals.md),
[`deload-life-stress`](../evidence.md#deload-life-stress--limited)).

- [x] `RecoveryTrend.lifeStress` reads the latest yes or no stress answer of the last 14 days.
- [x] Today asks the stress question first when a proposal would show and no answer exists.
- [x] A yes offers a steadier week (`DeloadPlan.stressAware`) with reasons and what may help; a no keeps the deload.
- [x] An accepted steadier week is stored (`DeloadRecord.forLifeStress`), applied in the logger and named on Today.
- [x] Tests: answer windows, no points from stress alone, plan choice, explanation, accepted week.
- [x] Follow-ups moved to tasks 8–10.

### 8. Stress-aware running advice

- [ ] Let `RecoveryTrend.lifeStress == .reported` shape the run advice (`EasyRunAdvisor`, planned runs on Today):
  keep the run, cap it at easy effort and skip intervals or tempo while stress is reported. Cite
  [`deload-life-stress`](../evidence.md#deload-life-stress--limited); do not claim that harder runs relieve stress.
- [ ] Tests: a planned interval session becomes an easy run with the reason shown; a "no" answer changes nothing.

Finish line: strength and running agree on the week an athlete under stress is offered.

### 9. Fewer repeat questions and an expiry the athlete can see

- [ ] A skipped or "not sure" answer asks again the next day while a proposal shows. Decide whether to ask at most
  every 3 days, and whether the card should say "Answered yes on 14 Nov" with a way to change it.
- [ ] Let a "yes" end earlier: a later "no" already overrides it; add a way to say "it's over" from the card.
- [ ] Tests cover skip, unsure, a later no, and the 14-day expiry (`RecoveryTrend.stressWindowDays`).

### 10. Validate the steadier week

- [ ] Real-device check of the card, the question flow and the logger targets under the steadier week; record it in
  [#21](https://github.com/droidsam1/overreach/issues/21).
- [ ] Clinical review of the stress question and the "what may help" lines (shared with
  [readiness task 3](readiness-and-hybrid-planning.md#3-ask-a-question-that-changes-the-decision)).
- [ ] Revisit `DeloadPlan.stressAware` (75 % of sets, about 5 % less load, RPE 8) when evidence appears on training
  under life stress. Today the multipliers are heuristics, and the athlete's results after accepting a steadier
  week are not recorded. Consider asking how it went at the end of the week.
- [ ] Add a plain-language reading on stress and training to `FurtherReading` for `deload-life-stress`; pick a
  source that agrees with the register and note any caveat.
- [ ] Optional: ask for a stress answer when readiness alone is low for several days, not only before a deload.
