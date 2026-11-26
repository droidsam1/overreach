# Exchanging data with AI chat apps

Overreach and AI chat apps (ChatGPT, Claude, …) exchange versioned JSON messages through the share sheet, the
clipboard or files (ADR-0017). This page is the field reference. The context pack links to it so an assistant can
read it.

## Versioning

- Every message has `format` (e.g. `overreach.context`) and an integer `version`.
- Adding an optional field keeps the version. Renaming or removing a field, or changing its meaning or unit, raises
  it.
- Absent fields mean "unknown" or "not set", never zero.
- Units: weight in kg, distance in m, duration in s, heart rate in bpm, HRV in ms. Days are `YYYY-MM-DD` in the
  user's calendar; instants are ISO 8601 in UTC.

## `overreach.context` v1 — app → AI

Shared from **Plan → Ask AI**. The JSON attachment contains the context data.
For **Plan my next block**, the shareable text also includes the reply schema, an example, the request and any
training availability the user enters. Health data and the cycle tracking setting are separate opt-ins, both off
by default. Without health data, the export excludes profile biometrics, check-ins, daily metrics, the daily
assessment, strength watch summaries, and heart rate, load and training effect from runs. The daily assessment is also excluded when cycle tracking is configured and the cycle setting
is kept private. Training notes are
included and can contain information the user entered manually.

The context's top-level fields:

| Field | Content |
|---|---|
| `format`, `version`, `about` | `overreach.context`, `1`, and a sentence saying what the data is |
| `generatedAt`, `app`, `units` | When it was made, by which app version, and in which units |
| `period` | `from` / `to` days the sessions, check-ins and metrics cover (4 weeks, 12 weeks or 6 months) |
| `athlete` | `sex`, `birthYear`, `bodyMassKg`, `maxHeartRate`, `restingHeartRate`, `cycleTracking`; `goal` (`kind`: `strength`, `hypertrophy`, `general` or `hybrid`; `targetDate`; `priorityLifts` by name; `priority`: `running` or `strength` for a hybrid goal, absent when balanced); `declaredBlocks` (`focus`, `start`, `plannedWeeks`, `name`, `routines` by name, `sessionsPerWeek`) |
| `catalog` | Names of every exercise in the app. Proposals should use these names. |
| `exercises` | Exercises used in the period, in routines or with their own settings: `name`, `equipment`, `primaryMuscles`, `secondaryMuscles`, `isCustom`, and `progression` when the user changed the defaults |
| `routines` | `id`, `name`, `focus`, `exercises` (names, in order), `prescriptions` (`exercise`, `scheme`) when the routine has its own sets and reps |
| `sessions` | Optional `rotationAdjustments` (see below). Oldest first: `id`, `date`, `startedAt`, `durationSeconds`, `name`, `focus`, `source`, `sessionRPE`, `notes`, and `exercises` with `exercise` (name), `notes`, `sets` and `countsForProgression` (`false` when the app excludes the exercise from progression, such as after a cap or an unfinished workout), and `watch` when a watch recorded the same workout (`source`, `averageHeartRate`, `maxHeartRate`, Garmin `trainingLoad` in its own units, `aerobicTrainingEffect`, `anaerobicTrainingEffect`) |
| `exerciseTrends` | Per exercise in the period: `exposures`, `status` (`progressing`, `holding`, `stalled`, `notEnoughData`, judged over the last year with a working exposure in the last 28 days), `lastWorkingWeightKg`, and `estimatedOneRepMaxKg` per session (`date`, `kg`) |
| `checkIns` | `date`, `isSick`, `energy` (1–5), `soreness` (1–5), `note` |
| `dailyMetrics` | Per day and `source`: HRV, its statistic (`hrvMetric`: Garmin `rmssd` or Apple Watch `sdnn`, never comparable) and its baseline, resting heart rate, sleep (total, deep, REM, score), body battery, stress, steps, VO2max, training readiness, acute load, recovery time |
| `today` | Optional local readiness and deload decisions for `period.to`, and `training`: what was already done that day. See the decision fields below. |
| `runs` | `date`, `startedAt`, `source`, `durationSeconds`, `distanceMeters`, `paceSecondsPerKm`, heart rate, elevation, training load and effect; when the watch recorded them, `movingDurationSeconds`, `lapCount` and the run/walk split (see below) |
| `rotationAdjustments` | Optional accepted schedule changes in the period, including pending ones. Each has `plannedDay`, optional `movedToDay`, optional `replacementSlotID` and `displacedSlotID`, and an `outcome`. |

### Rotation adjustments

A session's optional `rotationAdjustments` lists the recorded changes that applied to that workout.
Each outcome has an `action` (`swapped`, `postponed`, or `capped`) and may have `carryover`
(`light`, `notable`, or `unknown`), `reason` (`runCarryover`, `readiness`, `heavyLegsBeforeRun`,
or `other`), and `maximumRPE` for a cap. A postponed workout can also have a cap. Older
recorded changes can omit the carry-over level. Schedule slot IDs identify the originating
routine by UUID or use a `name:` prefix for rotations inferred from workout names.

### Values

- **Hybrid running goal:** `athlete.goal.running` has `distanceMeters`, optional `targetSeconds` and `aimsForPainFree`.
  Optional `athlete.goal.runningSchedule` contains entries with an `id`, local `day`, `purpose` (`easy`,
  `intervals`, `tempo`, `threshold`, `long`, `race`, `rest`), optional `durationMinutes` and `distanceMeters`, and
  `completed` when a recorded result has been confirmed. Optional `prescription` includes `repetitions`,
  `recoverySeconds`, `intensityBasis` and `intensityTarget`. The target is seconds per kilometre for `pace`,
  the zone number for `heartRateZone` and a 1–10 rating for `perceivedEffort`. Optional `racePriority` is
  `primary` or `secondary`. Moved entries keep their `originalDay`. `athlete.goal.nextRun` skips entries marked
  `postponed`, which remain in the calendar.

- **Run/walk split:** optional, added after v1 shipped (ADR-0043). `runWalk` has `running`, `walking` and `standing`,
  each summing the watch's segments of that kind: `distanceMeters`, `durationSeconds`, `segments`,
  `longestSegmentMeters` and `averageCadence` (steps per minute). With a split, `runningPaceSecondsPerKm` is the pace
  of the running segments only and `longestContinuousRunMeters` the longest running segment. Absent for Apple Health
  runs and watches without run/walk detection: read `paceSecondsPerKm`, which includes walk breaks, and treat the
  whole run as unknown in how it split.
- **Set:** `weightKg`, `reps`, `rpe`, `durationSeconds`, `distanceMeters`. `kind` is absent for working sets,
  otherwise `warmup`, `dropSet` or `failure`.
- **RPE:** on the reps-in-reserve scale, so RPE 8 means about 2 reps were left. It is absent when not logged.
- **Focus:** `strength`, `hypertrophy`, `mixed` or `endurance`.
- **Progression scheme** (`type`):
  - `doubleProgression`: `sets` × `minReps`–`maxReps`. Reps are added first, then load.
  - `linearLoad`: `sets` × `reps`. Load is added after a complete session.
  - `repCycle`: rotates through `repBlocks`.
  - `rpeBased`: `sets` × `reps` at `targetRPE`, with the load taken from the estimated 1RM.
- **Exercise trend status:** these are the app's [progression rules](design/progression-engine.md). An exercise
  outside the current routine or rotation can keep its history and omit a current stall by reporting `notEnoughData`.
- **Decision fields:** `today.readiness` is `green`, `amber`, `red` or `unknown`. `today.reasons` lists stable English rule
  identifiers such as `hrvBelowBaseline` and `shortSleep`. `today.deload.state` is `none`, `inProgress`,
  `confirmBreak` or `proposed`. A proposal includes `today.deload.signals`, for example `liftsStalled` and
  `rpeCreep`. `hrvTrendBelowBaseline` counts sustained changes to the rolling HRV average used for deload advice.
  `hrvBelowBaseline` refers to the comparable readings used by today's readiness assessment.
  `today.training` has `strength` and `run` (completed today) and `lowerBody` (`none`, `today` or `yesterdayHeavy`);
  the app holds back an unplanned run after lower-body work, so do not propose a second session or such a run.
  The export omits private check-in answers and their corresponding reason identifiers. The readiness level and
  deload state still reflect the full assessment shown in Today.

The pack also lists `imports`: the formats the app can read back, with this reference.

## `overreach.plan` v1 — AI → app

The user copies the reply format from **Plan → Ask AI → Copy the reply format** into the chat when they want
routines, exercise settings or a multi-week plan. The AI answers with one JSON code block. The user pastes the whole answer, or opens
it as a file. The app shows what would change and saves nothing until the user confirms.

```json
{
  "format": "overreach.plan",
  "version": 1,
  "routines": [
    { "id": "upper-a", "name": "Upper A", "focus": "strength",
      "exercises": ["Bench Press (Barbell)", "Bent Over Row (Barbell)"],
      "prescriptions": [
        { "exercise": "Bench Press (Barbell)",
          "scheme": { "type": "rpeBased", "sets": 5, "reps": 3, "targetRPE": 8 } }
      ] }
  ],
  "exerciseSettings": [
    { "exercise": "Bench Press (Barbell)", "focus": "strength",
      "scheme": { "type": "rpeBased", "sets": 4, "reps": 4, "targetRPE": 8 },
      "incrementKg": 2.5, "isMainLift": true }
  ],
  "startDate": "2027-01-04",
  "blocks": [
    { "name": "Strength", "focus": "strength", "weeks": 6, "routines": ["upper-a"] }
  ]
}
```

### Routines

| Field | Content |
|---|---|
| `id` | Stable key chosen by the AI. Importing a routine with the same `id` again updates it. Without an `id`, a routine with the same name is updated. |
| `name` | Required. |
| `focus` | Optional: `strength`, `hypertrophy`, `mixed` or `endurance`. |
| `exercises` | Required. Names in order. They are matched to the catalog by name or alias, ignoring case, accents and extra spaces. |
| `maxDurationMinutes` | Optional session time budget, 1–1440 minutes. Used in the import preview. |
| `prescriptions` | Optional. `exercise` (one of the routine's exercises) and `scheme` (as in exercise settings). In sessions started from this routine, that scheme replaces the exercise's own. This is how one lift can be 5 × 3 in a strength block and 3 × 8–12 in a hypertrophy block. The app still sets the load from recent sessions. |

An `id` taken from the context pack (`routines[].id`) updates that routine.

### Exercise settings

Settings are keyed by `exercise`, and fields left out keep their current value.

- **`focus`:** declares the exercise's focus. If its scheme was the one suggested for the previous focus, it changes
  to the one suggested for the new focus.
- **`scheme`:** replaces the scheme. `sets` must be 1–10, reps 1–50 and `targetRPE` 5–10 (8 if left out).
- **`incrementKg`:** 0–20.
- **`isMainLift`:** `true` or `false`.

### Blocks

`blocks` lists a multi-week plan in order. Each block starts the day after the previous one ends. The first starts
on `startDate` (`YYYY-MM-DD`), or on the day of the import.

| Field | Content |
|---|---|
| `name` | Optional, e.g. "Strength". |
| `focus` | Required: `strength`, `hypertrophy`, `mixed` or `endurance`. |
| `weeks` | Required, 1–52. |
| `routines` | Optional. Routine `id`s or names, from this plan or already in the app, in rotation order. |
| `sessionsPerWeek` | Optional, 1–14. Strength sessions planned each week; absent = one per routine. |

- **Saved as declared blocks** in the profile (ADR-0013). Blocks that start before the plan are kept, and declared
  blocks from the plan's start on are replaced. Focus checks treat a matching streak as intentional.
- **Up next.** Train shows the running block's next session, with its week ("Strength · week 2 of 6"). Routines
  rotate: the next one follows the routine of the last session started from the block, so a missed day moves the
  plan back rather than skipping a session. Sessions not started from one of its routines do not move it.
- **Follow-up.** Train shows this week's planned and completed sessions, and proposes changes (ADR-0019,
  `docs/evidence.md`): rest while ill, ease back in after a break of 14 days or more, and after two weeks below
  two thirds of the planned sessions, fewer sessions a week and a longer block. The user accepts or ignores each.
  When a session of the running block is due today and not done, the follow-up also reads today's recovery
  assessment, the same one Today shows (ADR-0035): an amber light proposes an easy session, a red one a recovery day
  (a walk or a very easy session, light if lifting), and warning signs, illness or pain skipping it. The proposal
  names the signals and their evidence, is for today only and changes nothing in the stored plan. A green or unknown
  light, missing readings, a finished session or no running block add nothing. An illness keeps its own advice alone.

### JSON Schema

The format is also a JSON Schema (draft 2020-12): [`schemas/overreach.plan.v1.schema.json`](schemas/overreach.plan.v1.schema.json).

- **In the reply format.** The schema is part of what the user copies into the chat, and the context pack links it
  in `imports`.
- **No extra fields.** It has types, required fields, allowed values and ranges, and `additionalProperties: false`.
- **Guidance in chat apps.** Chat apps cannot enforce a schema, so the app still validates everything. A test keeps
  the schema, the published file and the app's validation identical.

### Validation

- **All or nothing.** Any problem blocks the whole import, so a plan is never half-applied. Examples are an unknown
  exercise (the closest catalog name is suggested), an empty or unnamed routine, a repeated `id`, or a value out of
  range.
- **Correction.** The app writes a correction in English for the user to paste back into the chat. Each point
  names the field path (`exerciseSettings[0].scheme.sets is 30; expected 1 to 10`). Broken JSON gets its line,
  column, what was expected and the line itself, with hints for trailing commas, curly quotes and truncated text.
- **Workload.** The preview warns when estimated working sets and standard rests exceed the routine's time budget.
  It also flags the highest weekly fractional set totals in each block above the app's 20-set guide. It uses the
  routine rotation and the settings that would apply after import. See `docs/evidence.md` for the duration
  heuristic and volume dose-response.

- **Ignored fields.** Fields the format does not have, or that the scheme type does not use (e.g. `reps` in a
  double progression), are listed as warnings. They do not block the import, and the correction can ask the AI to
  remove them.
- **Versions.** A newer version is refused with a request to update the app. Every version documented here stays
  readable.
