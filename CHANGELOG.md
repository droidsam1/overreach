# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
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
