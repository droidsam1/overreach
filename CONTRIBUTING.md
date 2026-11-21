# Contributing to Overreach

Thanks for your interest! Overreach is a small project; these rules keep it maintainable.

## Before you start

- Read [`AGENTS.md`](AGENTS.md) for the module layout and dependency rules, and [`CODING_STANDARDS.md`](CODING_STANDARDS.md) for the coding rules.
- For anything bigger than a bug fix, open an issue first so we can agree on the approach.
- Architectural changes need an ADR in `docs/adr/` (copy the template in `0000-template.md`).

## Workflow

1. Fork and create a branch: `feat/short-description`, `fix/short-description` or `docs/...`.
2. Keep pull requests focused: one feature or fix per PR.
3. Write tests for logic in `OverreachCore`. UI changes should include a SwiftUI preview.
4. Run the compact local check before pushing: `python3 scripts/check-local.py` (Windows: `py -3 ...`). It also
   registers the String Catalog merge driver for your clone.
5. Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`,
   `test:`, `chore:`.
6. Update `CHANGELOG.md` under *Unreleased* when the change is user-visible.

### Parallel PRs

When open PRs change the same files, fetch both current branch heads and preview their merge with
`git merge-tree --write-tree origin/branch-a origin/branch-b`. This leaves the checkout intact. If the preview
reports conflicts, agree on the integration order and rerun it after either head changes.

### CI and merge

Record the PR head SHA with `gh pr view 123 --json headRefOid --jq .headRefOid`. Once checks appear for that
revision, follow them with `gh pr checks 123 --watch`. If a check fails, use `python3 scripts/ci-failures.py 123`
to see the failures. After a push, start with the new head SHA. When the checks pass, use
`gh pr merge 123 --match-head-commit CHECKED_SHA` to merge the revision you verified.

## Code guidelines

- Swift 6 with strict concurrency; no warnings.
- Features never import other features or concrete data modules — depend on `Domain` protocols.
- Views only render (ADR-0014): logic, filtering and rule texts go in the feature's presentation module in
  `OverreachCore`, with tests.
- All metrics are optional; handle missing data gracefully.
- User-facing strings go through the String Catalog in English, Spanish and Galician (ADR-0015).
- Accessibility: support Dynamic Type and VoiceOver in every new view.
- No secrets, personal data or real health exports in the repository. Use anonymised fixtures.

## Contributor agreement

By contributing, you agree that your contribution is licensed under the project's license and that the
maintainer may relicense the project in the future. (The exact license is still being decided; this
section will be updated with a DCO or CLA when it is.)

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).
