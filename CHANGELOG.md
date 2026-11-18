# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Presentation layer (ADR-0014): screen state, intents and texts move to `<Feature>Presentation` modules in
  `OverreachCore` (Linux-testable); `Feature*` modules only render. `DesignSystem` no longer knows domain types,
  and SwiftLint guards the boundary (no `Analytics` in UI code, no `.filter`/`.sorted` in views).
- `scripts/test-core.sh` / `.ps1` run the core and presentation tests in Docker (same image as CI).

### Added
- Per-exercise progression settings (#14): from an exercise, choose the scheme and its parameters, load
  increment (including microplates), focus and main lift, with defaults from the focus and equipment. Changes
  update the targets of an open session; sets already logged are kept.
- Routines (#15): create, edit, reorder and delete session templates with a name, focus and exercises from the
  Train tab, start a session from one with targets prefilled by the progression engine, or save a past session
  as a routine from History. Routines are included in backups and follow exercise merges.
- Custom exercises (#17): create them from the Exercises screen with name, other names, equipment and muscles.
  Names already used by another exercise are rejected; custom and imported exercises can be renamed and keep
  their old name for future imports. They appear in the logger and session-editing pickers.
- Exercises screen (Settings → Exercises, #13): imported exercises without muscles listed first with a badge;
  assign primary/secondary muscles and equipment, copy them from similar catalog exercises (name matching
  across Spanish aliases, accents and plurals), or merge into another exercise (history, progression settings
  and the name as alias move to the target).
- Backup and restore (#9): versioned JSON backup into an iCloud Drive folder after every session and when the
  app goes to the background, 14 days of dated copies, manual export, restore from file (merged by id, no
  duplicates) and a restore offer on a fresh install.
- Plan tab: goal (with target date and priority lifts), current block (declared or detected), next-block
  advice, balance findings and the plan for the coming months.
- Train tab: session focus (auto or declared), per-exercise focus and suggested rest; the focus picks the
  default progression scheme.
- Settings: import a Strong CSV with a preview (sessions, sets, new exercises, skipped lines).
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
