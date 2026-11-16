# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Training focus (strength, hypertrophy, mixed, endurance) declared per block/session/exercise or inferred
  from the sets; focus prescriptions (reps, RPE, %1RM, rest, scheme); balance findings against the goal; block
  suggestions and a plan up to a year ahead (ADR-0013, `docs/design/training-focus.md`).
- SwiftData persistence (`SwiftDataStore`): CloudKit-compatible records storing versioned JSON, built-in
  catalog merged with custom exercises, profile and per-exercise progression settings (ADR-0004).
- Train tab: live session logger with sets prefilled from the progression engine, target reasons with their
  evidence level and stall suggestions; only completed sets are saved.
- History tab: past sessions with sets, tonnage and e1RM per set; swipe to delete.
- Progression engine (`Analytics`): next-session targets for double progression, linear load, rep cycles and
  RPE-based schemes; RPE/RIR load prescription; stall detection with ordered suggestions; deload proposals
  from training signals. Every reason carries its evidence level (`docs/evidence.md`).
- Evidence-first policy for all recommendation logic (ADR-0012) and evidence register (`docs/evidence.md`).
- Domain types: `AthleteProfile` (sex, cycle tracking mode, walking routine), menstrual cycle and daily
  activity types, `EvidenceLevel`/`EvidenceReference`, and `ProfileRepository`, `CycleSource`,
  `ActivitySource` protocols.
- Strong CSV importer (`StrongImport`): header-based columns, `,`/`;` delimiters, warm-up/failure/drop sets,
  durations, kg/lb, stable ids for idempotent re-imports, unknown exercises flagged for muscle mapping.
- Built-in exercise catalog (73 exercises, Strong-style names, Spanish aliases, stable ids).
- Import strategy (ADR-0011) and guide with an AI prompt to convert free-form notes (`docs/import.md`).
- Phase 0 foundation: repository structure, `OverreachCore` and `OverreachKit` packages, XcodeGen app
  target, domain model, first analytics functions with tests, CI, documentation and ADRs.
- Progression engine design (`docs/design/progression-engine.md`).
- Cycle-aware training plan: ADR-0009 and `docs/design/cycle-aware-training.md`.
- Daily activity plan: ADR-0010 and `docs/design/daily-activity.md`.
- Build IPA workflow and guide for installing the app without a Mac (Sideloadly/AltStore).
