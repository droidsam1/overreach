# 0015 — Localization: one String Catalog, English keys

- **Status:** Accepted
- **Date:** 2026-11-18

## Context

The app must be usable in English, Spanish and Galician, and adding a language should not touch feature code.
Texts come from two places: SwiftUI views (`LocalizedStringKey`) and presentation models in `OverreachCore`,
which also build and test on Linux, where String Catalogs are not available.

## Decision

1. All translations live in one catalog, `App/Resources/Localizable.xcstrings`. SwiftUI and `String(localized:)`
   look in the main bundle by default, so packages need no resources of their own. The English text is the key.
2. Models use `L10n.text("…")`. Sentences with values use `L10n.format("Step {1} of {2}", a, b)`, so each language
   can reorder them. Interpolating into `L10n.text` is not allowed because the key would change with the value.
3. A literal `%` is passed as a value, never written in a key, so it cannot be read as a format specifier.
4. Views keep literal keys. Long ones use a multi-line literal, because `"a" + "b"` turns `Text` into verbatim text.
5. `scripts/check-localization.py` runs in CI. It fails on a missing, unused or incomplete string, or when a
   translation changes the values of its key.
6. Exercise names stay as they are: built-in names match Strong exports, and search already finds them by their
   Spanish aliases. *Superseded by ADR-0031: built-in exercises are shown with a Spanish name in Spanish and
   Galician; the stored name stays English.*

## Consequences

- A new language means adding it to both catalogs (`Localizable`, `InfoPlist`), `CFBundleLocalizations` and the
  script's list.
- Plural variants are not modelled yet. Translations prefer wordings that read well with any number.
