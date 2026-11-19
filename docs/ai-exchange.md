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

## Import messages — AI → app

Planned in issue #34: routines and exercise settings first, then training blocks. Each item will carry an `id` so
that importing it again updates it instead of duplicating it.
