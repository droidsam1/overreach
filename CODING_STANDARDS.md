# Coding standards

Judgment rules for writing and reviewing Overreach code. A reviewer applies the sections that match the files in
the diff. Rules a tool can decide are listed at the end and are not repeated here.

## Swift and concurrency

- Swift 6 with strict concurrency. Domain types are `Sendable` value types; repositories are actors or `Sendable`
  protocols with `async` APIs.
- SwiftUI with `@Observable` models (`@MainActor`); no third-party architecture frameworks (ADR-0003).

## Presentation (ADR-0014)

- `XModel` and its screen state live in `XPresentation` (OverreachCore); `XView` in `FeatureX` renders state and
  calls intents.
- Views keep layout, styling, accessibility, static copy and purely visual `@State` (sheet open, focus). Rule-based
  conditions, computations over data and texts derived from rules belong in the model.
- One model per screen or flow; sub-screens get a model from the parent.
- Presentation tests are the feature's contract: a redesign is safe when they pass.
- Interface changes follow the [iPhone UX guide](docs/design/iphone-ux.md): action hierarchy, progressive
  disclosure, before/after usability checks.

## Data

- Daily data is keyed by `CalendarDay` (year/month/day in the user's calendar), never by a raw `Date`.
- Store SI units (kg, meters, seconds, ms for HRV); convert only for display.
- Every metric is optional. Missing data degrades gracefully: no crash, no blocked screen.

## Recommendations (ADR-0012)

- Anything that produces a recommendation returns its reasons, each with an evidence level.
- A rule that recommends, proposes or evaluates (progression, stalls, deloads, readiness, load, cycle, walking,
  nutrition) rests on the most robust recent evidence: current meta-analyses, position stands and RCTs, searched
  before writing the rule. Where evidence runs out, use a labelled heuristic.
- Record the evidence in [docs/evidence.md](docs/evidence.md) and cite its key in code with `EvidenceReference`;
  `check-repo.py` fails on a key with no entry.

## Stored data (ADR-0018)

- A new field in a persisted type is optional or decoded with a default.
- A change to existing stored data bumps the backup format and adds a migration step in `BackupCodec.migrate`.

## Localization (ADR-0015)

- User-facing strings go through `App/Resources/Localizable.xcstrings` with English keys and es and gl
  translations. Models use `L10n.text` or `L10n.format("Step {1} of {2}", …)`.
- Code, comments and docs are in English. Spanish and Galician appear only in translations and quoted examples.

## Tests

- Swift Testing (`import Testing`, `@Test`, `#expect`).
- Pure logic in `OverreachCore` is covered, with realistic fixtures.

## Releases and decisions

- Each release adds its highlights to `ReleaseNotes.all` (OnboardingPresentation) for "What's new". A feature
  worth showing to new users also gets a page in the first-run tour.
- A non-obvious decision gets an ADR in `docs/adr/` from the [template](docs/adr/0000-template.md).
- No secrets in the repository; signing settings live in `App/Config/Local.xcconfig` (git-ignored).

## Checked by tools

| Rule | Check |
| --- | --- |
| UI imports no `Analytics`; views don't `.filter`/`.sorted` data | SwiftLint custom rules (`.swiftlint.yml`) |
| Lines a branch changes add no lint warnings | `new-lint-warnings.py` via `check-local.py` and CI |
| Strings are in the catalog, translated, with matching placeholders; catalogs sorted | `check-localization.py` |
| Unique ADR numbers, `# NNNN — Title` headings | `check-repo.py` |
| Evidence keys used in code have an entry in `docs/evidence.md` | `check-repo.py` |
| Each "Ready to implement" row in `docs/priorities.md` links one unique issue | `check-repo.py` |
| Frozen v1 backup fixture unchanged | `check-repo.py` |
| Every released version has "What's new" highlights | `check-repo.py` |
| Skill copies in sync, agent guide links resolve, no tracked bytecode | `check-repo.py` |
| Module dependencies | `Package.swift` |
