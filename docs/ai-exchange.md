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

Shared from **Plan → Ask AI**. It is raw data with no instructions. Its top-level fields:

| Field | Content |
|---|---|
| `format`, `version`, `about` | `overreach.context`, `1`, and a sentence saying what the data is |
| `generatedAt`, `app`, `units` | When it was made, by which app version, and in which units |
| `period` | `from` / `to` days the sessions, check-ins and metrics cover (4 weeks, 12 weeks or 6 months) |
| `athlete` | `sex`, `birthYear`, `bodyMassKg`, `maxHeartRate`, `restingHeartRate`, `cycleTracking`; `goal` (`kind`: `strength`, `hypertrophy`, `general` or `hybrid`; `targetDate`; `priorityLifts` by name); `declaredBlocks` (`focus`, `start`, `plannedWeeks`, `name`, `routines` by name, `sessionsPerWeek`) |
| `catalog` | Names of every exercise in the app. Proposals should use these names. |
| `exercises` | Exercises used in the period, in routines or with their own settings: `name`, `equipment`, `primaryMuscles`, `secondaryMuscles`, `isCustom`, and `progression` when the user changed the defaults |
| `routines` | `id`, `name`, `focus`, `exercises` (names, in order), `prescriptions` (`exercise`, `scheme`) when the routine has its own sets and reps |
| `sessions` | Oldest first: `id`, `date`, `startedAt`, `durationSeconds`, `name`, `focus`, `source`, `sessionRPE`, `notes`, and `exercises` with `exercise` (name), `notes`, `sets` and `countsForProgression` (`false` only for an exercise left unfinished, which the app ignores for progression), and `watch` when a watch recorded the same workout (`source`, `averageHeartRate`, `maxHeartRate`, Garmin `trainingLoad` in its own units, `aerobicTrainingEffect`, `anaerobicTrainingEffect`) |
| `exerciseTrends` | Per exercise in the period: `exposures`, `status` (`progressing`, `holding`, `stalled`, `notEnoughData`, judged over the last year), `lastWorkingWeightKg`, and `estimatedOneRepMaxKg` per session (`date`, `kg`) |
| `checkIns` | `date`, `isSick`, `energy` (1–5), `soreness` (1–5), `note` |
| `dailyMetrics` | Per day and `source`: HRV, its statistic (`hrvMetric`: Garmin `rmssd` or Apple Watch `sdnn`, never comparable) and its baseline, resting heart rate, sleep (total, deep, REM, score), body battery, stress, steps, VO2max, training readiness, acute load, recovery time |
| `runs` | `date`, `startedAt`, `source`, `durationSeconds`, `distanceMeters`, `paceSecondsPerKm`, heart rate, elevation, training load and effect |

### Values

- **Set:** `weightKg`, `reps`, `rpe`, `durationSeconds`, `distanceMeters`. `kind` is absent for working sets,
  otherwise `warmup`, `dropSet` or `failure`.
- **RPE:** on the reps-in-reserve scale, so RPE 8 means about 2 reps were left. It is absent when not logged.
- **Focus:** `strength`, `hypertrophy`, `mixed` or `endurance`.
- **Progression scheme** (`type`):
  - `doubleProgression`: `sets` × `minReps`–`maxReps`. Reps are added first, then load.
  - `linearLoad`: `sets` × `reps`. Load is added after a complete session.
  - `repCycle`: rotates through `repBlocks`.
  - `rpeBased`: `sets` × `reps` at `targetRPE`, with the load taken from the estimated 1RM.
- **Status:** these are the app's deterministic rules (`docs/design/progression-engine.md`), not a judgement on
  the athlete.

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
- **Ignored fields.** Fields the format does not have, or that the scheme type does not use (e.g. `reps` in a
  double progression), are listed as warnings. They do not block the import, and the correction can ask the AI to
  remove them.
- **Versions.** A newer version is refused with a request to update the app. Every version documented here stays
  readable.

Still to come: adjustments from HRV, resting heart rate and sleep, with the readiness rules of phase 2.
