# 0014 — Presentation layer: views only render, logic lives in OverreachCore

- **Status:** Accepted
- **Date:** 2026-11-17

## Context

The UI will change once the app is used on a real phone, and it must be possible to redesign any screen
without breaking a feature. ADR-0003 already puts logic in `@Observable` models, but:

- The models lived in `OverreachKit`, which only builds and tests on macOS. Without a Mac their tests only ran
  in CI.
- Views still held logic: an e1RM computed in `HistoryView`, target/rest lines composed in `WorkoutView`,
  search filters, the primary/secondary exclusivity in the exercise editor, goal rules in `PlanView`, rule
  texts (`ProgressionText`, `PlanText`) in UI modules.
- `DesignSystem` knew domain types (`TrainingFocus.title`, `SetKind`, `ExercisePicker` taking `[Exercise]`).

This is the standard split on mobile today: Android's architecture guide (UI elements + state holders that
expose UI state, unidirectional data flow, domain and data layers below) and SwiftUI's lightweight views with
`@Observable` models. Both also warn against over-abstraction.

## Decision

1. **Presentation modules in `OverreachCore`** (`Sources/Presentation/<Feature>Presentation`), one per feature,
   plus `PresentationKit` (display names, search, `L10n`). They hold the `@MainActor @Observable` models, the
   screen state (rows, drafts, confirmations with display-ready text), the intents, validation, filtering
   and every text derived from rules. They depend on `Domain`, `Analytics` and `PresentationKit`; never on
   SwiftUI or on another presentation module. They build and test on Linux.
2. **`Feature*` modules in `OverreachKit` are UI only.** They depend on their presentation module and
   `DesignSystem`, **not on `Analytics`**. `Package.swift` declares this; because SwiftPM still lets a target
   import transitive modules, SwiftLint fails on `import Analytics` in UI code and warns on `.filter`/`.sorted`
   in views. A view:
   - renders the model's state and calls its intents;
   - may keep purely visual `@State` (a sheet is open, keyboard focus, animation), never business state;
   - holds layout, styling, accessibility and static copy (titles, button labels);
   - contains no rule-based `if`, no computation and no `.filter`/`.sorted` over data.
3. **One model per screen or flow**, not per component. Sub-screens get a small model created by the parent
   model (e.g. `ExercisesModel.editor(for:)` → `ExerciseEditorModel`).
4. **Text from presentation goes through `L10n.text`** (String Catalog on Apple platforms, English on Linux).
   Static UI copy stays as `LocalizedStringKey` in the views.
5. **`DesignSystem` is domain-agnostic**: generic components taking display values (`StatusBadge` takes a title
   and a `StatusTone`; the feature's view decides which tone each state gets).
6. Presentation tests are the feature's contract: a redesigned view is safe if they still pass.
   `scripts/test-core.sh` / `scripts/test-core.ps1` run them locally in Docker (`swift:6.0`, same as CI).

## Consequences

- Screens can be rewritten or restyled by touching only `Feature*` files.
- All feature logic is testable without a Mac, locally and in the Linux CI job.
- More modules (one presentation module per feature) and some display types that mirror domain types.
- Views may still import `Domain` for value types used as picker tags; they must not use it for logic.
