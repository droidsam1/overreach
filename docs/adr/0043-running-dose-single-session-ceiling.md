# 0043 — Running dose: a single-session ceiling, the watch's run/walk split, no weekly cap

- **Status:** Accepted
- **Date:** 2026-11-23

## Context

Today offers a run/walk example towards a pain-free distance goal (#251). The first version added 0.5 km of running
plus a walk break after every run without pain, so one session could be up to 50% longer than anything run
recently. It also treated every run as continuous, because the domain had only total distance and duration.

Two questions needed an answer: how much a session may grow, and over what period. The evidence reviewed on
2026-11-23 (sources in `docs/evidence.md`, `run-walk-progression`):

- **Single session.** Frandsen et al., BJSM 2025: 5,205 runners wearing Garmin watches, 18 months, 588,071 sessions.
  A session more than 10% longer than the longest run of the previous 30 days had higher overuse-injury rates
  (adjusted HRR 1.64 for 10–30%, 1.52 for 30–100%, 2.28 for more than 100%). Up to 10% or shorter was the reference.
- **Week.** In the same cohort, the week-to-week ratio showed no association and the acute:chronic workload ratio
  an inverse one. The 10% weekly rule did not reduce injuries in a randomized trial of 532 novices (Buist 2008:
  20.8% vs 20.3%). A 2014 novice cohort linked only increases above 30% over two weeks to some injury types.
- **Pain.** Clinical pain-monitoring models tolerate mild pain (up to 5/10) that settles by the next morning
  (Silbernagel 2007). Overreach recorded pain as yes or no, and only on runs linked to a plan, until #256.

All of it is observational or from small trials; no study validates a specific run/walk dose.

Garmin's activity list, which the app already downloads (ADR-0022), includes the watch's run/walk detection:
`splitSummaries` of type `RWD_RUN`, `RWD_WALK` and `RWD_STAND`, each with distance, time, number of segments, the
longest segment and cadence. Per-lap values are not in the list.

## Decision

1. **The ceiling is per session.** A suggested session, walking included, stays within 10% of the longest run of the
   last 30 days and never passes the goal distance. Every recent run counts for the ceiling, painful or not: it
   measures exposure, not tolerance. Rounded down to 100 m.
2. **No weekly or cycle cap.** The newest and largest cohort found no protective weekly ratio, and the weekly 10% rule
   failed in a trial. Adding one would block progress without evidence. Revisit if new evidence appears.
3. **Progress inside the ceiling is a heuristic.** It lengthens the longest continuous running stretch without
   reported pain by 0.25 km and repeats it with the athlete's own typical walk break until the ceiling. Pain after the
   last run or no run for 14 days repeats the last pain-free session; pain twice in a row steps back. These doses are
   product defaults labelled as heuristic in the UI and the register, never as research findings.
4. **Pain holds above a threshold or when it does not settle.** Any run, planned or not, can carry a 0–10 pain
   answer for during and after, and whether it settled by the next morning (#256, `RunPainReport`, stored by run).
   Pain up to 3/10 (configurable) that settled by morning does not hold; more, unsettled or not yet confirmed does.
   Two holds in a row step back. Yes/no answers from before keep the cautious reading: any pain holds. Silbernagel
   tolerates up to 5/10; 3/10 is the more cautious product default because it is not tied to one injury.
5. **The watch's run/walk split is a domain value.** `RunActivity` gains `runWalk` (`RunWalkSplits`: running,
   walking and standing parts), `lapCount` and `movingDurationSeconds`, with derived `runningPaceSecondsPerKm` and
   `longestContinuousRunMeters`. `GarminImport` decodes them from the activity list with no extra request. They are
   optional: Apple Health runs and older caches have none, and rules fall back to the whole run as one continuous
   stretch.
6. **Distance, never pace, sets the effort.** Outdoor runs with stops make pace an unreliable target; the
   conversational-pace cue stays.

## Consequences

- Growth is slower for runners without walk breaks (+10% per session) and faster for run/walk athletes, whose walking
  turns into running inside the same distance.
- The ceiling reads only recorded runs: a run missing from Health or Garmin lowers it, which errs on the safe side.
- The study merged runs less than 15 minutes apart into one session; Overreach does not yet (#257).
- Today asks about pain after any recorded run for a pain-free goal, so the progression no longer advances through
  unreported pain. Mild pain waits for the morning answer before it counts as tolerated.
- Per-lap values need FIT decoding or another endpoint (#259). Showing the new markers in History and the AI
  exchange is #258. Applying the ceiling to planned and imported runs is #257.
