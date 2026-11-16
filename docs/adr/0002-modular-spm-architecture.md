# 0002 — Modular architecture with two Swift packages

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

The app combines very different concerns: a workout logger, several data sources (Health, Garmin, CSV),
analytics, AI providers and many screens. We want clear ownership per component, fast tests, and the
ability to add capabilities (nutrition, other watches) without touching existing code.

## Decision

Split the code into Swift Package Manager modules with explicit dependencies, in two packages:

- **OverreachCore** — pure Swift, no Apple-only frameworks: `Domain`, `Analytics`, `StrongImport`, `Reports`.
  It builds and tests on Linux, so CI for the core logic is fast and cheap.
- **OverreachKit** — modules that need Apple frameworks: `Persistence` (SwiftData), `HealthKitSource`,
  `GarminSource`, `AIKit`, `DesignSystem` and one `Feature*` module per screen/flow.

The `App` target is the composition root: it is the only place that instantiates concrete implementations
and injects them into features as `Domain` protocols.

Rules: `Domain` depends on nothing; features never import other features or concrete data modules.

## Consequences

- Each module compiles and is tested in isolation; SwiftUI previews stay fast.
- Data sources can be swapped or mocked (previews, tests, a user without Garmin).
- More `Package.swift` boilerplate, and cross-feature navigation must go through the App's routing.
