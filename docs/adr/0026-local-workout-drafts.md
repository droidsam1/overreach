# 0026 — Save one active workout as a local draft

- **Status:** Accepted
- **Date:** 2026-11-20

## Context

The live logger holds editable values and a rest timer before it commits a finished session. iOS can
terminate the process in the background without giving it a final save opportunity.

## Decision

- Replace one versioned draft file atomically on the device as the workout changes. Store the session identity,
  routine, target context, exercise and set order, values, completion flags, notes and the rest deadline.
  The draft stays outside the SwiftData schema and the app's portable backups.
- Open Train on launch when a draft is present. The athlete can resume it or explicitly discard it. An unreadable
  draft stays on disk until the athlete retries or confirms discard.
- Assign the workout its permanent ID at the start. Commit the finished workout before removing the draft. If
  the app stops between these operations, recovery checks for that ID in History and removes the stale draft.
  If the check fails, keep the draft and allow a retry. The finished-workout format stays compatible with ADR-0018.

## Consequences

- A relaunch can restore a workout without adding partial work to History, progression or plan completion.
- Existing app exports and reinstalls restore only data supported by the portable backup format. The file is
  intended for process relaunch and a normal app update on the same installation.
