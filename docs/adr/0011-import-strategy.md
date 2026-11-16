# 0011 — Importing training history: one canonical CSV, three ways in

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Users arrive in three situations:

1. **Strong users** with a CSV export (years of data: the maintainer's export has 626 sessions, 12,004 sets).
2. **New users** with no history (e.g. Laura) who start from zero.
3. **Users with free-form notes** (Notes app, a notebook, a spreadsheet) in no standard format.

Writing a parser for every possible note style is a losing game, and a wrong parse silently corrupts the
history the progression engine relies on.

## Decision

- **One canonical import format: Strong's CSV columns** (`Date, Workout Name, Duration, Exercise Name,
  Set Order, Weight, Reps, Distance, Seconds, RPE`, plus optional `Notes`, `Workout Notes`). It is simple,
  documented, and already what Strong users have. `StrongCSVImporter` reads it deterministically.
- **Strong users:** import the export directly. The app asks for the weight unit (the file does not say).
- **New users:** start from the built-in `ExerciseCatalog` (Strong-style names, Spanish aliases, stable ids)
  and routine templates. Nothing to import.
- **Notes:** the app offers a ready-made prompt (`docs/import.md`). The user pastes it with their notes into
  ChatGPT/Claude, which returns CSV in the canonical format; the user pastes or shares that CSV back into the
  app, which validates it with the same importer and shows a preview before saving. The AI does the fuzzy
  interpretation; the app keeps the deterministic validation.
- Unknown exercise names become custom exercises flagged `needsMuscleMapping`; the import flow asks the user
  to map them before finishing (otherwise their volume would not count towards any muscle group).
- Imported ids are stable (`UUID.stable`), so re-importing the same data does not duplicate sessions.

## Consequences

- A single importer to test and maintain; notes support needs no parser.
- The notes path depends on an AI chat the user already has. A built-in heuristic notes parser can be added
  later behind the same preview, if users ask for it.
- The CSV format is also a natural export format (phase 1 backup can include it for portability).
