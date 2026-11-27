# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Recovery shows sleep timing variation alongside the number of nights with bed and wake times. Training start
  time variation appears as a descriptive measurement (#349).

### Added
- Backups include imported Garmin activities and daily metrics for offline restore (#324).
- Ask AI lets you select health metric groups and preview and confirm the report before sharing (#324).
- AI context exports include usual sleep and training times, timing variations and evidence-linked observations
  when health data sharing is enabled (#348).
- Recovery shows a "Sleep and training times" card from the last 28 days: usual bedtime, wake time and training
  start, and only the observations the timing analysis returns, each with its evidence level. It appears after a
  week of nights or five sessions and never changes load, readiness or the plan (#347).
- Sleep regularity now uses a Sleep Regularity Index built from bed and wake times of consecutive nights (or the
  sleep-midpoint spread when nights have gaps) instead of bedtime spread alone, so shifting wake times count and a
  weekend-only lie-in stays social jetlag (#351).
- AI plan previews show weekly session counts, flag routines over their time budget, and flag blocks with high weekly
  volume. Per-exercise rest intervals from the plan drive the workout timer, and marked deloads are checked against
  the previous block. The next-block request shares the reply template and optional availability with the context. Health data
  and the cycle tracking setting are opt-in (#34).
- Weather has a provider picker: Open-Meteo (no key, account or card; the default for new installs), OpenWeather One
  Call or an OpenWeather free key (3-hour steps, no past-run weather). Each option lists its setup, card, resolution,
  past-run and terms limits, has its own onboarding, links its attribution on Today and History, and switching clears
  the saved forecast but keeps the OpenWeather key. Installs with an OpenWeather key keep it (#372, #373, #374).
- Weather settings show a masked "API key saved" state with Replace key and Disconnect, and a four-step guide to
  getting an OpenWeather key that checks it before saving (#362, #363).
- The Today weather button is grey until weather is set up, then shows a coloured condition icon with the
  temperature, or a progress or warning badge while loading or when the forecast failed (#364).
- The weather forecast is kept between launches, shows "Updated HH:mm" and refreshes on pull without exceeding the
  daily request budget (#365).
- Today can show a local hourly weather forecast and likely dry and sunny periods for running or walks.
- The timing evidence review now covers long-term prevention: exercise hour and disease risk (no preferred time, cohorts
  disagree), weekend-warrior patterns (never a fault), consistent training time (habit, not circadian) and meal timing,
  with a health-lens test in the design note and an ADR-0045 amendment.
- Evidence review of sleep and training timing (zeitgebers): regular sleep, social jetlag, evening exercise and
  exercise phase shifts, with five register entries, ADR-0045 and a design note. `CircadianTiming` computes usual
  bedtime, wake and training times and returns neutral insights; it is not yet shown in the app (#347).
- Recovery & Progress shows observed 1, 5 and 10 km running times, recorded strength results and eligible
  estimated 1RM trends for the last 30 or 90 days. Select a chart point or session row to open its source.
  Plan progress, deloads and rest history remain available from Progress.
- Performance cards label recorded results, estimates and time upper bounds and show each with its own chart
  symbol (#333).
- Progress can compare Garmin heart rate during steady running blocks at similar pace and slope. Confirm the
  sensor for each run when its source is unknown, and open the running activities linked from the comparison.
- Today asks how the legs respond to a warm-up after a recent run when the next rotation slot works the legs.
  The answer can keep the session lighter, offer torso or leave the leg session pending.
- Plan shows the pending strength routine and recent recorded runs in the hybrid calendar, marking run days
  without logged strength. Today previews the resulting rotation before a swap or postponement is accepted.
- Today and Recovery & Progress show a one-time hint when a new section becomes available.
- The plan follow-up in Train uses today's recovery assessment, the one Today shows. When a session of the running block is due, an amber light proposes keeping it easy, a red light a recovery day, and warning signs, illness or pain skipping it, naming the signals and their evidence. The proposal is for today only: the stored plan, schedule and weekly targets stay as entered. Green or unavailable readings, a session already done and no running block propose nothing.
- Garmin runs of the last 14 days keep each lap's distance, time, pace, heart rate, cadence and elevation (`RunLap`), fetched from the activity's splits after the activity list: at most 5 more requests per sync, kept in the cache and never asked twice. A Garmin that does not serve the splits leaves the laps empty and the sync unaffected.
- Today suggests a swap or postponement after a recorded run. Accepting saves the change, and a swap starts the
  replacement workout. Keep plan hides the offer for the day. Why explains the run and readiness, and a capped
  workout uses no load increase and stays out of progression checks.
- Analytics decides what a recorded run means for the next leg-heavy session (`RotationAdjustment.suggest`, ADR-0044): keep after an easy run with green readiness, otherwise swap with the first later slot with no (then moderate) leg demand, postpone a day, or keep with no load increase and top sets at RPE 8. A swap never drops a slot or puts two heavy-leg sessions within 48 h; upper-body slots, red readiness and a missing rotation suggest nothing.
- Recorded runs include descent when Garmin or Apple Health supplies it. The next-lift carry-over rule
  uses descent per kilometre, with ascent as a fallback.
- Swaps and one-day postponements of the strength rotation can be recorded (`RotationAdjustment`, ADR-0044), stored in the profile and in backups (older backups load without them). Rotation detection and the projection tolerate a recorded swap or postponement, so Today keeps knowing the rotation; without a record, any change of order or rhythm still drops it.
- Analytics rates how much a recorded run carries over into the next lift (`RunCarryover`, ADR-0044): notable after a hard, long, hilly or unaccustomed run, less than 24 h before the lift, or with soreness or pain that holds; light otherwise; unknown without a duration. Runs without training effect, such as Apple Health runs, are rated on the other criteria.
- Sections appear only when there is data behind them (ADR-0041). Today shows only the rest-day hero and the way to connect a source until a reading or a recorded workout or run exists, then adds the Recovery and History links one by one. Recovery & Progress lists Recovery with a reading, Recent load with a logged session or run and Progress with a goal or a lift trained twice, hides trend charts without points, and says what unlocks them when nothing is available yet.
- Today offers an optional "Good day for an easy run" (with your dog's name when you have one) under the rest
  hero on a rest day of your strength rotation that suits a run, with the run/walk example, a "Not today" button
  that hides it for the rest of the day, also after closing and reopening the app, and "Not today? Thursday also works" when another good day is left. The week strip
  marks those days with a small dot. It never shows on a red light, with symptoms, after a run or session today or
  right after leg work.
- Running: Today asks about pain after any recorded run when your goal is pain-free, with or without a plan: 0–10 during
  and after, and the next day whether it settled by morning. Mild pain (up to 3/10) that settled no longer holds the
  run/walk progression; stronger or unsettled pain does, and two holds in a row step back.
- Plan warns when a dated run is planned more than 10% longer than your longest run of the previous 30 days, the
  single-session spike linked to overuse injuries, and offers to shorten it to that distance. Runs less than 15
  minutes apart count as one, and a run planned by time is converted with your recent pace. It never blocks saving.
- History's run detail shows the watch's split when it has one: running and walking distance and time, the longest
  continuous running stretch, running-only pace, moving time and laps. The context pack (`runs[].runWalk` and
  related optional fields) and the Markdown report share the same values.

- Garmin runs now keep the lap count, moving time and the watch's run/walk detection: running, walking and standing
  distance, time, number of segments, the longest continuous running stretch and cadence, from the activity list
  Overreach already downloads. Running pace can be read without the walk breaks.

- The exercise picker in Train and in the routine editor can create an exercise search does not find. The typed
  name is kept, equipment comes from the name ("barra", "mancuernas"…) and muscles from the most similar exercise,
  so most of the time it is one tap on Add. A name that an exercise already answers to offers that one instead.

- 52 common exercises join the catalog, with Spanish names: barbell lunges, walking and reverse lunges, split
  squats, trap bar and single-leg Romanian deadlifts, push press, landmine press, Nordic curls, hip adduction,
  cable crunches, Pallof press, box jumps, farmer's walks, sled pushes and more.
- The logger can reorder exercises mid-session: long-press an exercise's name (or pick "Reorder exercises" in
  the session options) and the session collapses to names you drag, then Done. Each exercise's menu also has
  Move up and Move down. Sets and typed values move with the exercise.

- Warm-up sets are added from a button under each exercise's sets, next to "Add set": the first tap adds the
  suggested warm-up, later taps add one more warm-up set before the working sets.

- Today asks "With <dog>?" about your latest recent walk, with Yes and No. One tap saves the answer, and the
  app learns the times you usually walk the dog. You can set the dog's name in onboarding and Settings; History comes next.

- The profile can store the dog's name, and the app can now work out which walks to ask "With <dog>?" about:
  every walk at first, then only near the times you usually walk the dog. No screen yet.

- Walks can carry a dog tag. A matcher tags the walks a tracker's movement windows overlap, the athlete's own
  answer always wins, and the tag survives merging the Garmin and Apple Health copies of a walk. No screen yet.

- Recovery & Progress shows 30- and 90-day trends: HRV, resting heart rate and sleep in the Recovery detail,
  weekly strength sets and running distance in Recent load. Each chart names its metric, unit and interval,
  keeps days without a reading as gaps, and has a text summary for VoiceOver. Only readings from the series and
  source of the latest reading are plotted, and a usual-range band appears only when Garmin reports one.

- Recovery & Progress compares completed and planned strength sessions by imported block and week.

- Today compares planned runs with conversational alternatives and accounts for nearby races, quality runs and
  scheduled strength. Keep the session, switch to the easy run or review a clear date for the original run in Plan.

- Plan supports structured run targets, race priority and postponement in the hybrid calendar.
- Plan leads with your next scheduled sessions (tap one to move or change it), the current block and a goal
  summary; goal editing opens from the summary. Recovery periods, lifts to unblock and linked running results moved
  to a Progress section in Recovery & Progress, one tap from Plan's "View progress". A recent break question stays
  in Plan beside the block decision it affects.
- Recovery & Progress has a dedicated Recovery tab for the iPhone navigation trial. Settings opens from the
  gear button on Today, which still links directly to recovery readings.
- History shows Apple Health strength workouts and credits Apple Health when it supplies a copy of a Garmin workout.
- Today asks whether you have felt more stressed than usual before proposing a deload. If you say yes, it offers
  a steadier week (about 75 % of the sets, RPE 8 at most, keep moving) instead of a deload, explains why, and the
  workout logger applies it. The answer stays on your device and out of shared context.
- Review ambiguous Garmin strength matches in History, link or separate workouts, and undo matches from session details.
- Hybrid goals have a Running first, Strength first or Balanced priority in Plan. It is saved with the goal and
  shared in the context export.
- History lets you review competing Garmin and Apple Health run matches, link originals and undo a link.
  Choices persist across syncs and apply in both the list and calendar.
- Recent load in Recovery & Progress shows today's walking and how it compares with your usual day. Today
  keeps walking advice relevant to the day's training.
- The workout logger can fill the open sets of an exercise with last time's weight and reps from its menu, only when
  you choose it; effort and sets already done are left as they are.
- Recovery & Progress opens from Today with "View recovery". It lists HRV, resting heart rate and sleep against
  your usual range, with the source, latest reading, coverage and baseline of each, plus Garmin's estimates and
  the last 7 days of strength, running and everyday movement next to your usual week. Today's metric tiles moved
  there; a failing source or missing data is explained and can be retried.
- Today puts an unfinished workout first and highlights the next useful action when there is no workout to resume.
  Recommendation details, today's metrics and recent training have labeled entry points.
- Plan lists the lifts to unblock: each current stalled lift says since when it stopped progressing, its best set
  and one next step, with the evidence and other options on its detail. Smaller jumps, a rep range or a new rep
  range can be applied to that exercise's settings after confirmation.
- Today gives one main reason for a suggested deload. Open the explanation for all the signals, your last rest
  and recovery history, the changes to your next strength session and the supporting research.
- Today and Plan ask about the latest lighter training periods, with the strength and running activity recorded
  for those dates. Plan offers up to two recent questions and keeps the rest under Older periods.
- Count weeks without recorded training as rest separately for strength and running. After longer breaks, Today
  allows time to rebuild strength training before proposing a deload and suggests an easy return to running (ADR-0037).
- Walking beyond the usual day can contribute to the weekly strength load comparison used for deload advice.
  Today shows walking minutes against the usual day and suggests an easy warm-up after a walking spike if a
  leg session or run is scheduled (ADR-0010).
- Everyday movement counts walks and hikes recorded on a Garmin watch and walks nobody started on a watch, found in
  Apple Health's minute-by-minute steps (at least 10 minutes of steady walking outside any workout). The usual day
  now includes the dog walks and the commute, so only real departures from it stand out (ADR-0010).
- Today compares your steps with your usual day over the last four weeks. A walk or hike from Apple Health that is
  an hour or more above your usual walking is mentioned before leg work or a run, three very quiet days suggest a
  walk, and a red day suggests an easy walk, or keeping your usual dog walks easy (ADR-0010).
- Today leads with the recommended action and its main reasons. The explanation shows how many comparable HRV
  readings were low, what other readings say and where the readings and references came from.
- Today's HRV explanation uses when you actually slept: a run that ends after midnight still counts before last
  night's reading. A recorded run you linked to a planned race is marked as a race, and the explanation shows your
  comparable HRV before and after it (ADR-0034).
- Today asks one optional check-in question about symptoms, fatigue, running pain or unusual stress when the
  answer can inform the session. Editing the response updates today's advice, and the new answers stay local.
- Readiness records every input it read: where it came from, whether it was compared, missing, stale or out of
  range, the reference it was compared with and the outcome. The AI report lists them, and Today says when HRV
  was skipped because a watch stopped syncing or its readings were implausible. Daytime and sleep HRV readings
  are no longer mixed in one baseline, and implausible readings are ignored (ADR-0032).
- Today recognises the order you rotate through your workouts (A, B, C, D, then A again) and bases the easy
  strength option and the deload on the session you have next. Without a plan you can choose the next session, and a
  deload proposal shows each exercise of that session with fewer sets and less load, or a general example.
- Before suggesting a deload, Today asks whether a recent break it could not confirm was a rest; if it was, no new
  deload is suggested. Lighter sessions after a break no longer count as a performance drop.
- After the first session with an exercise, Train repeats it as a starting point and lets you preview and choose
  how to progress (reps, load or a wave); progression then waits for logged effort before advancing.
- Built-in exercises show their Spanish name when the app is in Spanish or Galician; search finds exercises by
  their English or Spanish names, and Strong imports and AI plans that use the Spanish names resolve to them.
- Cycle-aware recovery: with a natural cycle and regular periods in Apple Health, Today compares HRV and resting
  heart rate with the same window (follicular or luteal) of your previous cycles, and the deload signals do the
  same. Until two cycles have data, a low luteal HRV is context and the resting-HR threshold allows for the usual
  rise before a period. Hormonal contraception and menopause keep the overall baseline. The app never estimates
  ovulation or fertility (ADR-0009).
- Assign a routine or strength rest day alongside running in the hybrid calendar.
  On amber days, Today compares a scheduled routine with a lighter option and shows a starting weight when
  recent easy sets support it. With no strength session due, ask for an example with **I want to lift today**.
- The hybrid running calendar supports several dated runs, races and rest days, with optional links to recorded runs.
- Hybrid goals can include a running distance, time or pain-free target and the next planned running day.
- In Plan, linked runs show progress toward a hybrid running goal and can record pain during or after the run.
- Today can use the running goal, recent runs and recovery signals to propose a conversational run or a plan adjustment.
- Today suggests a deload week when your training shows fatigue (stalled lifts, dropping maxes or rising RPE) and
  your recovery has been poor all week (HRV, resting heart rate, sleep or check-ins), with the reasons. Start it
  or postpone it for a week; recovery alone never suggests a deload. During the deload week, workout targets have
  half the sets, about 10 % less load and RPE 7 at most.
- Log a watch-only strength workout from History: the new session starts with the watch's times, and once saved it
  shows the watch's heart rate and load. Apple Watch strength workouts appear too, and a Garmin workout and its
  Apple Health copy count once.
- The AI context adds what the watch recorded during each session (`sessions[].watch`).
- On an amber day, Today can show an optional light strength example alongside the next routine or recent session.
- Today explains low HRV in plain language, puts it alongside measured recovery and recent training, and links to the research.
- Today can offer one optional check-in question about symptoms or unusual stress when HRV stays below your range.
- History lists logged strength sessions, watch-only strength and runs together, with activity and source
  filters. Open any run to see its pace, heart rate and available training metrics.
- Garmin sync revisits the last seven days of activities to pick up workouts uploaded by the watch days later.
- Today shows seven days of completed runs, strength sessions and recovery readings together by local date.
- Today explains gaps in HRV coverage and shows how many comparable readings were low when the trend drops.
- Resume an interrupted workout with its routine, sets, notes and rest timer. Overreach saves the draft on
  the device and opens Train on relaunch so you can resume or discard it.
- History shows Garmin heart rate, training load and training effect on matched strength sessions. Watch-only
  strength workouts appear in the same list with their own read-only details.
- "Learn more" under explanations (ADR-0030): the readiness light, the logger's targets and stall suggestions, the
  plan check and the Plan screen link to the studies behind each rule and to curated plain-language reading
  (Fitness Revolucionario in Spanish), the user's language first. Only readings that agree with the evidence
  register are linked; `scripts/check-reading-links.py` reports dead links.
- Today says which numbers are the devices' estimates: sleep stages, Body Battery, stress and VO2max.
- Plan check (#34, ADR-0019). Train shows this week's planned and completed sessions. When sessions keep being
  missed, it proposes fewer sessions a week (with the same weekly sets, results are about the same) and a longer
  block. After a break of two weeks or more it says to keep the plan and ease back in, and after an "ill"
  check-in, to rest until the symptoms ease. Each proposal says why, with its evidence level, and nothing changes
  until you accept it. Plans can set `sessionsPerWeek` per block.
- Train from a plan (#34, ADR-0019). An AI plan can now include training blocks (`blocks`, `startDate`) and
  sets and reps for an exercise in one routine only (`routines[].prescriptions`), so a lift can be 5 × 3 in a
  strength block and 3 × 8–12 in a hypertrophy block. Train shows "Up next in your plan", with the block and week,
  and starts it in one tap. The engine still sets every load from recent sessions. Routines rotate, so a missed
  day never skips a session. The context pack shows the plan, so the AI can revise it.
- History → Calendar: a month calendar (Monday first) with strength days, runs and a steps ring per day that
  fills against the month's average. It has a legend, month totals (sessions, runs, km run, steps per day) and,
  for a tapped day, its sessions (opening their detail), runs (distance, duration, pace, heart rate) and steps.
  Runs from Garmin and Apple Health are combined and counted once, with training load and training effect shown
  when available. Steps come from Apple Health. The calendar still shows sessions and available runs if one source
  fails. List or calendar is remembered.
- Today reads Apple Health. It shows last night's sleep with deep and REM, HRV, resting heart rate, steps and
  VO2max, each with its 7-day average and where it came from, plus a "Connect Apple Health" button. Runs from
  Health are read too (shown in a later change). Sleep from several sources is merged without counting it twice
  (`HealthAggregation`).
- History → a session → "View summary" reopens its report, compared with the target the engine gave it then.
- An animated first-run tour (welcome, logging, coaching, AI, safety) before the setup. Every page can be skipped,
  it can be swiped, and it respects Reduce Motion.
- "What's new" after an update, with the highlights of every version since the last one seen. New installs do not
  see it, because the tour covers it.
- Backups you can rely on (ADR-0018): Settings warns, with a badge, when your data is only on the iPhone. The
  first-run setup offers "Restore from a backup". After a reinstall, choosing the backup folder offers to restore
  it. A frozen v1 backup in the tests guarantees future versions keep loading today's data, and there is a
  migration step for format changes.
- Session summary after finishing. It shows duration, working sets, volume and effective sets per muscle, and how
  many exercises met their target. Per exercise: above, on or below target with the numbers, effort against plan,
  personal records, a new stall and next time's target. It compares volume with the last session of the same name
  and can be shared with an AI app.
- Log effort as RPE or as reps in reserve (RIR), chosen from "How to log sets". Sets still store RPE, so history,
  targets and the AI context do not change. The guide explains how to rate effort and the common bias of guessing
  about 1 rep too few (`rir-estimation`).
- "Stalled", "Holding" and "Progressing" explain why, with the numbers behind them (best estimated 1RM recently
  against before, missed targets) and the evidence level. Stall suggestions say why they help.
- Finishing with unfinished exercises asks whether they count for progression. Left out, they are saved and shown
  as unfinished in History, but the engine ignores them for targets and stalls. This can be changed later from
  the session editor.
- Settings → Appearance: light, dark or the same as the iPhone (the default).

### Fixed
- The hybrid calendar lists completed runs and strength sessions for the week shown in its calendar strip.
- Progress lists each lift once, most trained first, with a source filter when several sources have data. Running best times fall back to the recorded track when laps do not cover the distance, and the heart-rate sensor list shows only runs still to confirm.
- Plan's week now shows recorded runs and logged rest like Today, and a past day with no training counts as a
  rest day in both. The weather provider picker updates as soon as you pick one.
- Settings opens an editable training profile with a Save button for your goal, personal context, walking routine,
  dog name and devices.
- Today's **Recovery** tile switches to the Recovery tab, like History, instead of pushing a copy of it inside Today.
- Editing a finished session now lets you add, change and clear each exercise's notes.
- Today asks "With your dog?" after a recent recorded run when your profile includes a dog. Yes and No are saved
  for that run, and you can add or change the answer in its History detail.
- The recovery signals behind a deload proposal judge each of the last 7 days against a full 60-day baseline; without
  cycle tracking the oldest days used a shorter one.
- Current stalls require progression-eligible work in the last 28 days. Today labels stall signals as
  main lifts only when those lifts are marked main.
- A lift is stalled or progressing in the same way in the workout, Plan, Today's deload advice and the AI context:
  all use the settings of the routine the lift was last trained in, and Plan no longer counts exercises left
  unfinished (ADR-0035).
- Today, Plan and the workout count from the same last deload or break. Today no longer says "51 weeks since your
  last deload" when Plan shows one two weeks ago, and proposes no new deload in the week after one. With no deload in
  the history it says how many weeks of training it looked at (ADR-0035).
- Garmin sync counts each activity once when the same activity appears on multiple API pages.
- The progression engine ignored the kind of set: warm-up sets in the history now no longer count for targets,
  stalls or the working weight.

### Changed
- Progress shows imported Strong and Overreach lifting sessions together in one chart per exercise and metric.
- First-run setup asks two things: your goal and your devices, where you also choose how to start (train, import from
  Strong or restore a backup). The sex, cycle and walking questions moved to Today, shown one at a time only when
  the answer would change a recommendation (a cycle question when recovery readings exist and you never answered
  it, a dog question once Health shows walks) and never asked twice; "Later" brings it back tomorrow. Settings →
  Training profile still edits everything.
- The run/walk example for a pain-free goal now keeps the whole session, walking included, within 10% of your
  longest run in the last 30 days, the single-session spike linked to overuse injury in a 5,200-runner cohort. Progress
  lengthens the continuous running stretch (from the watch's run/walk detection when available) and uses your own
  typical walk break. There is no weekly cap: weekly ratios showed no link to injury in that study.
- Today knows your next lifting day without a dated plan: when you repeat the same workouts in a fixed order at a
  steady rhythm (A, B, C, D on alternate days), the rotation is projected onto the calendar and a leg session
  tomorrow keeps today's optional run short. Each rest day is also scored as a running window (best, good, avoid)
  by its leg-heavy neighbours, ready for Today to show. A dated plan still wins.
- For a pain-free running goal, Today shows a small run/walk example in distance blocks (for example "2 km easy ·
  walk 0.5 km · 0.5 km easy"). It starts from your longest recent run without reported pain, adds one small step after
  a run without pain, repeats after pain or a missed fortnight and goes back a step after pain twice in a row. A
  heuristic, not a research finding.
- Reorder exercises in a session by touching one for a moment and dragging without lifting your finger: the session
  folds to compact cards, the others slide out of the way with a light tick, the screen scrolls near its edges, and
  letting go unfolds the sets with the moved exercise in view. Move up / Move down stay in the exercise menu and as
  VoiceOver actions, and Reduce Motion drops the sliding.
- Today is drawn as cards (ADR-0042): a hero with the readiness ring, verdict, one reason, up to three recovery
  signals with their trend and one action; Your week with the seven days and progress; one prompt with a one-tap
  check-in; and tiles for **Why · Options · Recovery · History**. **Why** shows what weighs, a chart or gauge per
  reason and its evidence. After training the hero shows the session totals and records. At the largest text sizes
  the cards stack instead of cutting text, every colour comes with a symbol or word, VoiceOver reads a replaced run
  as "Planned: …", and the ring does not animate with Reduce Motion.
- The Assistant context now says what you already trained today (`today.training`: strength, run and leg load), and
  Plan no longer suggests today for a new run once training or tired legs hold an unplanned one back. Today, the
  Assistant and Plan read one shared answer.
- Today no longer offers an unplanned run after lower-body strength: with leg work today, or a heavy leg session
  yesterday (8 or more working sets, or a set at RPE 9), it says to leave the run for another day and why. A run that
  is in your plan stays, kept short, and a running priority is not changed. The rule is a heuristic from concurrent
  training research, not a recovery clock.
- After you train, Today says so ("You've trained today. Recovery is part of the plan.") instead of recommending
  another session. A lift or a run finished today, from the logger, Apple Health or Garmin, ends the
  recommendation unless the plan has another dated session for the day; **Log another workout** stays one tap away.
- When the advice is to rest, Today's action is **Rest today**: it logs the day as a deliberate rest and
  confirms with "Rest logged. Recovery is training too.", tomorrow's plan when there is one, and an undo.
  History marks the day with a small moon, not as an activity. There is no streak to break.
- Today ends with one row of links: **Why · Other options · Recovery · History**. Reasons, evidence, guidance,
  the deload details and everyday movement moved to **Why this recommendation?**; the optional run and easy
  strength session moved to **Other options**. A test keeps Today to four blocks.
- Under the verdict Today shows at most one question or notice at a time: a failed source, the break
  confirmation, the check-in, connecting Apple Health or Garmin, or the dog walk, in that order. Answering one
  shows the next on the next refresh. Connecting a source stays in Settings.
- Today leads with the readiness verdict, its main reason and one action. Start a strength routine, open the
  run instructions or view Recovery on a rest day. Further reasons are under “Why this recommendation?”.
- Today shows confirmed dog walks separately, with their time, recorded distance and progress against your usual
  daily walks. Easy-walk advice refers to your dog by name when you have entered one.
- The report after finishing a workout leads with every real record of the session, not only the first: a new best
  estimated 1RM, more reps than ever at a load and, new, the most volume ever for a lift in one session. Equal is
  not a record and a lift's first session has nothing to beat. Completing a set now animates its checkmark (not
  with Reduce Motion), and all haptics go through one helper so a setting can turn them off.
- Plan opens with your real progress: "This week: 3 of 4 sessions" (planned strength sessions and runs against
  the ones done) and "Block: week 2 of 5" while a declared block runs, each with a bar. Only linked runs count as
  done, rest days and postponed runs are not counted as missed, and without a plan nothing is shown.
- Today puts the next action first and shows planned training before the detailed recovery explanation.
- The workout logger leads with the first exercise and its sets. "How to log sets" and the session focus moved to
  the session options menu, and the optional warm-up advice now follows the first exercise. Each exercise shows
  what you did last time, with its date, under today's target, completing a set gives a haptic confirmation, and
  the report after finishing leads with "Workout saved to History" and the session's record, when there is one.
- Evidence review of November 2026 (`docs/evidence-review-2026-11.md`):
  - The acute:chronic workload ratio is replaced by this week's load against the usual week (the 3 weeks before),
    uncoupled; it is a weak deload signal and never an injury-risk measure.
  - For people who track a natural cycle, a low HRV is shown as possibly the cycle and does not make the light red
    on its own.
  - Sets count toward weekly volume from RPE 6 (was 7).
  - Red light: "Make it a recovery day" instead of "Rest"; fewer sessions keep "about the same muscle and nearly
    the same strength". Periodisation and walking-no-interference evidence levels lowered to moderate.
- Training and history editing adapt set controls to narrow screens and large text. The rest countdown stays
  compact, with time adjustments available on demand.
- History switches to a daily agenda when the monthly grid needs more room. Today prioritizes available
  recovery data and the Apple Health connection, and gives large metrics a single column.
- Plan leads with what to do next, the AI screen shows the report and reply steps in order, and first-run
  setup can open the Strong import screen directly.
- Easier weight and reps fields while logging. The whole field, unit included, is the tap target. Tapping selects
  the value so typing replaces it. A "Done" button above the keyboard and scrolling hide the keyboard. Values save
  as you type, so marking a set right after typing keeps them.

### Added
- Warm-up sets (evidence: `warm-up-specific`, `warm-up-ramp`). Main lifts and the first exercise for each muscle get
  a ramp to close to today's load with few reps; other exercises get one on demand from their menu. Warm-ups show
  as W, do not start the rest timer and are saved apart. An optional general warm-up is suggested until the
  first set.
- The reply format for AI answers includes a JSON Schema of `overreach.plan` v1, also published in
  `docs/schemas/`. Corrections for the AI now locate broken JSON (line, column, the line itself). Fields the app
  does not use are listed as warnings instead of being dropped silently.
- Bring an AI's answer back (#34, ADR-0017): copy the reply format into ChatGPT or Claude, then paste its answer or
  open it as a file. The app previews the routines and exercise settings it would create or update. A problem such
  as an unknown exercise blocks the import and gives a correction to paste back into the chat. Importing the same
  routine again updates it instead of duplicating it (`overreach.plan` v1).
- Plan → Ask AI (ADR-0017): shares your training as versioned raw data (`overreach.context` v1: sessions with notes,
  exercise settings, routines, goal, trends and health metrics) with ChatGPT, Claude or another chat app, as text or
  as a `.json` file, with an optional first request. The format is documented in `docs/ai-exchange.md`.

### Changed
- The reasons under each target now say what to do today with its numbers (for example "Today: drop to 72.5 kg and
  aim for 8 reps…"), and the RPE menu says how many reps in reserve each value means.
- Long session names wrap in the logger instead of being cut.

### Added
- Notes per exercise and for the whole session while logging, saved with the session and in backups.
- Each exercise in the logger can have its own focus (e.g. bench for strength in a hypertrophy session), from its
  menu. It recomputes the target, keeps sets already done and is remembered for the exercise.
- "How to log sets" in the logger: what to change after a set, the RPE scale and what notes are for.

### Removed
- The seven-day "Recent training and recovery" list on Today: History has the record, and the readiness explanation
  keeps the workouts that matter for today's light.

## [0.1.0] - 2026-11-18

First testable release, sideloaded without TestFlight. See the [tester guide](docs/beta-guide.es.md).

### Changed
- Presentation layer (ADR-0014): screen state, intents and texts move to `<Feature>Presentation` modules in
  `OverreachCore` (Linux-testable); `Feature*` modules only render. `DesignSystem` no longer knows domain types,
  and SwiftLint guards the boundary (no `Analytics` in UI code, no `.filter`/`.sorted` in views).
- `scripts/test-core.sh` / `.ps1` run the core and presentation tests in Docker (same image as CI).

### Added
- App icon, an accent colour for light and dark mode, clearer error messages, empty states for lists and searches,
  and better VoiceOver and large-text support (#21).
- Finished strength sessions are saved to Apple Health (#20), without duplicates when edited, and removed with
  the session (ADR-0016).
- Spanish and Galician (#19): every screen, message and training explanation follows the language chosen for the
  app, and a CI check keeps the translations complete (ADR-0015).
- Optional first-run setup (#18): goal, sex and cycle tracking, walking routine, then import from Strong or start
  from the catalog. Every step can be skipped, it is not shown to existing users or before a restore offer is
  answered, and it can be reopened from Settings → Training profile.
- Rest timer (#16): completing a set starts the suggested rest for the exercise's focus, with ±15 s, skip, the
  evidence behind the suggestion and a local notification when the app is in the background.
- Per-exercise progression settings (#14): from an exercise, choose the scheme and its parameters, load
  increment (including microplates), focus and main lift, with defaults from the focus and equipment. Changes
  update the targets of an open session; sets already logged are kept.
- Routines (#15): create, edit, reorder and delete session templates with a name, focus and exercises from the
  Train tab, start a session from one with targets prefilled by the progression engine, or save a past session
  as a routine from History. Routines are included in backups and follow exercise merges.
- Custom exercises (#17): create them from the Exercises screen with name, other names, equipment and muscles.
  Names already used by another exercise are rejected; custom and imported exercises can be renamed and keep
  their old name for future imports. They appear in the logger and session-editing pickers.
- Exercises screen (Settings → Exercises, #13): imported exercises without muscles listed first with a badge;
  assign primary/secondary muscles and equipment, copy them from similar catalog exercises (name matching
  across Spanish aliases, accents and plurals), or merge into another exercise (history, progression settings
  and the name as alias move to the target).
- Backup and restore (#9): versioned JSON backup into an iCloud Drive folder after every session and when the
  app goes to the background, 14 days of dated copies, manual export, restore from file (merged by id, no
  duplicates) and a restore offer on a fresh install.
- Plan tab: goal (with target date and priority lifts), current block (declared or detected), next-block
  advice, balance findings and the plan for the coming months.
- Train tab: session focus (auto or declared), per-exercise focus and suggested rest; the focus picks the
  default progression scheme.
- Settings: import a Strong CSV with a preview (sessions, sets, new exercises, skipped lines).
- Training focus (strength, hypertrophy, mixed, endurance) declared per block/session/exercise or inferred
  from the sets; focus prescriptions (reps, RPE, %1RM, rest, scheme); balance findings against the goal; block
  suggestions and a plan up to a year ahead (ADR-0013, `docs/design/training-focus.md`).
- SwiftData persistence (`SwiftDataStore`): CloudKit-compatible records storing versioned JSON, built-in
  catalog merged with custom exercises, profile and per-exercise progression settings (ADR-0004).
- Train tab: live session logger with sets prefilled from the progression engine, target reasons with their
  evidence level and stall suggestions; only completed sets are saved.
- History tab: past sessions with sets, tonnage and e1RM per set; swipe to delete.
- Progression engine (`Analytics`): next-session targets for double progression, linear load, rep cycles and
  RPE-based schemes; RPE/RIR load prescription; stall detection with ordered suggestions; deload proposals
  from training signals. Every reason carries its evidence level (`docs/evidence.md`).
- Evidence-first policy for all recommendation logic (ADR-0012) and evidence register (`docs/evidence.md`).
- Domain types: `AthleteProfile` (sex, cycle tracking mode, walking routine), menstrual cycle and daily
  activity types, `EvidenceLevel`/`EvidenceReference`, and `ProfileRepository`, `CycleSource`,
  `ActivitySource` protocols.
- Strong CSV importer (`StrongImport`): header-based columns, `,`/`;` delimiters, warm-up/failure/drop sets,
  durations, kg/lb, stable ids for idempotent re-imports, unknown exercises flagged for muscle mapping.
- Built-in exercise catalog (73 exercises, Strong-style names, Spanish aliases, stable ids).
- Import strategy (ADR-0011) and guide with an AI prompt to convert free-form notes (`docs/import.md`).
- Phase 0 foundation: repository structure, `OverreachCore` and `OverreachKit` packages, XcodeGen app
  target, domain model, first analytics functions with tests, CI, documentation and ADRs.
- Progression engine design (`docs/design/progression-engine.md`).
- Cycle-aware training plan: ADR-0009 and `docs/design/cycle-aware-training.md`.
- Daily activity plan: ADR-0010 and `docs/design/daily-activity.md`.
- Build IPA workflow and guide for installing the app without a Mac (Sideloadly/AltStore).
