# 0031 — Built-in exercises have a Spanish name

- Status: accepted
- Date: 2026-11-19

## Context

ADR-0015 kept exercise names in English: built-in names match Strong exports, and search already found
exercises by their Spanish aliases. In practice a Spanish-speaking user reads "Lat Pulldown (Cable)" in every
list, picker and summary, and the aliases are lowercase, accent-free search keys ("jalon al pecho"), not names
worth showing.

## Decision

1. Every built-in exercise in `ExerciseCatalog` gets a Spanish name next to its English one
   (`make("Lat Pulldown (Cable)", es: "Jalón al pecho (polea)", …)`), following the same "Name (equipment)"
   pattern. `ExerciseCatalogTests` fails if one is missing.
2. The stored name does not change. `Exercise.name` stays the English catalog name, so ids, Strong matching,
   backups (ADR-0018), reports and the AI exchange (ADR-0017) are untouched. The Spanish name is not persisted;
   it is looked up by id in the catalog, so existing installs and backups get it with no migration.
3. Presentation shows `Exercise.displayName`: the Spanish name when the app runs in Spanish or Galician
   (Galician gyms use the Spanish names; there is no Galician column yet), otherwise the stored name. Custom and
   imported exercises always show their own name. Lists and pickers sort by the displayed name.
4. Search and matching use `Exercise.knownNames` (name, Spanish name, aliases) in every language, so
   "press de banca" and "bench press" both find the exercise, and Strong imports or AI plans that use the
   Spanish names resolve to the built-in exercise.

## Consequences

- Adding a built-in exercise needs a Spanish name. A Galician column can be added the same way if needed.
- Markdown reports and AI context packs keep the English names, which the AI matches back reliably.
- On Linux the app language is always English, so presentation tests check Spanish through
  `displayName(language:)`.
