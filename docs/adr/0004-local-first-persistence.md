# 0004 — Local-first persistence, CloudKit-ready

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Data must survive a reinstall (ideally restored automatically from the user's iCloud), but there is no
backend and, during the prototype, no paid Apple Developer account. CloudKit sync requires the paid account.

## Decision

- Store data with SwiftData behind `Domain` repository protocols.
- Design the SwiftData model to be CloudKit-compatible from day one: every property optional or defaulted,
  no unique constraints, optional relationships with inverses.
- Prototype (free account): automatic JSON backup into an iCloud Drive folder chosen by the user
  (security-scoped bookmark), and restore from it after a reinstall.
- Phase 4 (paid account): enable the CloudKit container so data syncs and restores automatically.

## Implementation (v0.1)

- `BackupDocument` / `BackupCodec` (Domain): format version 1, tolerant decoding, refuses newer formats.
- `RepositoryBackupService` + `FolderBackupDestination` (Persistence): folder bookmark, `Overreach-backup.json`
  plus 14 dated copies; restore merges by id and keeps a profile already set up on the device.
- Triggers: after each finished session, when the app goes to the background, and manually in Settings.

## Consequences

- Turning on CloudKit later is a configuration change, not a data migration.
- CloudKit constraints limit some modelling choices (no `@Attribute(.unique)`).
- The JSON backup format is versioned and also serves as an export feature.
