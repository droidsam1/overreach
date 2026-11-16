# Contributing to Overreach

Thanks for your interest! Overreach is a small project; these rules keep it maintainable.

## Before you start

- Read [`CLAUDE.md`](CLAUDE.md) — it describes the module layout and the dependency rules.
- For anything bigger than a bug fix, open an issue first so we can agree on the approach.
- Architectural changes need an ADR in `docs/adr/` (copy the template in `0000-template.md`).

## Workflow

1. Fork and create a branch: `feat/short-description`, `fix/short-description` or `docs/...`.
2. Keep pull requests focused: one feature or fix per PR.
3. Write tests for logic in `OverreachCore`. UI changes should include a SwiftUI preview.
4. Run locally before pushing:
   ```bash
   swift test --package-path Packages/OverreachCore
   swiftlint
   swift format lint --recursive Packages App/Sources
   ```
5. Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`,
   `test:`, `chore:`.
6. Update `CHANGELOG.md` under *Unreleased* when the change is user-visible.

## Code guidelines

- Swift 6 with strict concurrency; no warnings.
- Features never import other features or concrete data modules — depend on `Domain` protocols.
- All metrics are optional; handle missing data gracefully.
- User-facing strings go through String Catalogs (English and Spanish).
- Accessibility: support Dynamic Type and VoiceOver in every new view.
- No secrets, personal data or real health exports in the repository. Use anonymised fixtures.

## Contributor agreement

By contributing, you agree that your contribution is licensed under the project's license and that the
maintainer may relicense the project in the future. (The exact license is still being decided; this
section will be updated with a DCO or CLA when it is.)

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
