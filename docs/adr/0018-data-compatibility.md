# 0018 — Stored data stays readable across versions

- Status: accepted
- Date: 2026-11-19

## Context

The app is used daily and updated often. New features add fields, for example biometrics, set kinds or effort
settings. Data written by any earlier version must keep loading:
- the on-device store, which keeps each record as JSON of the domain types (ADR-0004);
- backups, which are one JSON document;
- exports.

Data from a newer version must never be read as if it were understood.

## Decision

1. **Backups carry `formatVersion`** (now 1) and the app version that wrote them. A newer format is refused with
   a message to update the app.
2. **Additive changes keep the version.**
   - A new field is optional, or is decoded with `decodeIfPresent` and a default.
   - A new backup section defaults to empty.
   - This applies to every persisted type: sessions, entries, sets, exercises, routines, progression settings,
     check-ins and the profile.
3. **Breaking changes raise the version.** A rename, a new meaning or a different unit needs a JSON-to-JSON
   migration step in `BackupCodec.migrate` from each older version, and a frozen fixture of that version.
4. **Frozen fixtures.**
   - `BackupFormatV1Tests` holds a v1 backup with every type and field. It is never edited.
   - If a change makes it fail, the change broke existing data and must be made tolerant or versioned.
   - The store uses the same encoding, so the fixture covers it too.
5. **Restores merge by id.** Nothing is duplicated, and nothing on the device is removed.

## Consequences

- New biometrics and other optional data can be added freely. Old backups load with those fields empty.
- Any non-optional field added without a default fails a test before it ships.
- A format bump costs a migration step and a new fixture. That is deliberate.
