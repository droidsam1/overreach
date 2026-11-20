# 0023 — Don't write a strength workout to Apple Health twice

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

ADR-0016 writes every timed session logged in the app to Apple Health. Many people also start a strength activity
on their watch, and Garmin Connect (or the Apple Watch Workout app) writes that workout to Health too. Health then
shows two workouts for the same hour, and its totals count both. The watch's copy usually arrives later, when the
watch syncs, sometimes hours after the session was saved in the app.

## Decision

1. Before writing a session, the writer reads the strength workouts that **other apps** wrote to Health around that
   time (`HealthWorkoutWriter.strengthWorkoutsFromOtherSources`). If one is the same workout, the app does not write
   its own, and removes any copy it wrote before.
2. "The same workout" uses `StrengthActivityMatching` (ADR-0022, docs/design/garmin-integration.md): the intervals
   overlap by at least half of the shorter one, and pairing is one to one.
3. Because the watch's copy can arrive later, the app reconciles the last 14 days of sessions each time it comes
   to the foreground (and at launch). It removes its copy of any session another app now covers.
4. The watch's workout is kept, not ours: it has heart rate and calories, which ours lacks. Sets stay in the app.
5. Without read permission for workouts, HealthKit returns only the app's own workouts. The app then writes as
   before (best effort, ADR-0016).

## Consequences

- Health shows one workout per session, whichever device recorded it.
- If the person later deletes the watch's workout from Health, the app does not write its own back until the session
  is edited. This is rare and harmless.
- It works for any watch that writes to Health, with or without the Garmin integration.
