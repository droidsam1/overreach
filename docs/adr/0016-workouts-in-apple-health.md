# 0016 — Strength workouts in Apple Health

- **Status:** Accepted
- **Date:** 2026-11-18

## Context

Finished sessions should appear in Apple Health once, even if they are edited later. HealthKit workouts cannot be
modified: a change means writing a new workout and deleting the old one. Saving to Health can also be refused or
fail, and that must never put the training log at risk.

## Decision

1. Each workout stores the session id in `HKMetadataKeyExternalUUID`, and the workouts of a session are found by
   querying that key. Nothing is added to `StrengthSession`, so there is no migration, and the link survives a backup
   restored on the same Health data. HealthKit returns an app's own samples even without read permission.
2. Saving writes the new workout first and then deletes the previous ones. A failure can leave a duplicate until the
   next save, but never loses the workout.
3. Only sessions logged in the app with a positive duration are written. Imported and restored history is not, because
   it may already be in Health.
4. Editing touches Health only when the times change, since a workout holds nothing else from the session. Removing
   the end time, or deleting the session, removes the workout.
5. Writing happens after the session is saved and is best effort: permission is requested on the first write, and a
   refusal or error is ignored.

## Consequences

- Sets, exercises and calories are not sent to Health.
- A failed write is not retried until the session's times change.
