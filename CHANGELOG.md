# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Assign a routine or strength rest day alongside running in the hybrid calendar.
  On amber days, Today can compare the scheduled routine with a lighter option.
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
- Garmin sync counts each activity once when the same activity appears on multiple API pages.
- The progression engine ignored the kind of set: warm-up sets in the history now no longer count for targets,
  stalls or the working weight.

### Changed
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
