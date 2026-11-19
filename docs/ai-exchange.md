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
| `athlete` | `sex`, `birthYear`, `bodyMassKg`, `maxHeartRate`, `restingHeartRate`, `cycleTracking`; `goal` (`kind`: `strength`, `hypertrophy`, `general` or `hybrid`; `targetDate`; `priorityLifts` by name); `declaredBlocks` (`focus`, `start`, `plannedWeeks`) |
| `catalog` | Names of every exercise in the app. Proposals should use these names. |
| `exercises` | Exercises used in the period, in routines or with their own settings: `name`, `equipment`, `primaryMuscles`, `secondaryMuscles`, `isCustom`, and `progression` when the user changed the defaults |
| `routines` | `id`, `name`, `focus`, `exercises` (names, in order) |
| `sessions` | Oldest first: `id`, `date`, `startedAt`, `durationSeconds`, `name`, `focus`, `source`, `sessionRPE`, `notes`, and `exercises` with `exercise` (name), `notes` and `sets` |
| `exerciseTrends` | Per exercise in the period: `exposures`, `status` (`progressing`, `holding`, `stalled`, `notEnoughData`, judged over the last year), `lastWorkingWeightKg`, and `estimatedOneRepMaxKg` per session (`date`, `kg`) |
| `checkIns` | `date`, `isSick`, `energy` (1–5), `soreness` (1–5), `note` |
| `dailyMetrics` | Per day and `source`: HRV and its baseline, resting heart rate, sleep (total, deep, REM, score), body battery, stress, steps, VO2max, training readiness, acute load, recovery time |
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
routines or exercise settings. The AI answers with one JSON code block. The user pastes the whole answer, or opens
it as a file. The app shows what would change and saves nothing until the user confirms.

```json
{
  "format": "overreach.plan",
  "version": 1,
  "routines": [
    { "id": "upper-a", "name": "Upper A", "focus": "strength",
      "exercises": ["Bench Press (Barbell)", "Bent Over Row (Barbell)"] }
  ],
  "exerciseSettings": [
    { "exercise": "Bench Press (Barbell)", "focus": "strength",
      "scheme": { "type": "rpeBased", "sets": 4, "reps": 4, "targetRPE": 8 },
      "incrementKg": 2.5, "isMainLift": true }
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

### Exercise settings

Settings are keyed by `exercise`, and fields left out keep their current value.

- **`focus`:** declares the exercise's focus. If its scheme was the one suggested for the previous focus, it changes
  to the one suggested for the new focus.
- **`scheme`:** replaces the scheme. `sets` must be 1–10, reps 1–50 and `targetRPE` 5–10 (8 if left out).
- **`incrementKg`:** 0–20.
- **`isMainLift`:** `true` or `false`.

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

Still to come in #34: training blocks with weekly sessions and per-session prescriptions.
