# 0003 — Native SwiftUI + Observation, no third-party architecture framework

- **Status:** Accepted
- **Date:** 2026-11-16

## Context

Options for UI state management include The Composable Architecture (TCA), MVVM with Combine, or plain
SwiftUI with the Observation framework (`@Observable`, iOS 17+).

## Decision

Use plain SwiftUI with `@Observable` models annotated `@MainActor`. Each feature has `XView` + `XModel`;
the model receives its dependencies (Domain protocols) through its initializer and exposes async actions.
No external architecture dependency.

## Consequences

- Zero third-party dependencies in the UI layer; lower barrier for contributors.
- Testable models (inject fakes, call actions, assert state).
- We must keep discipline ourselves: no business logic in views, no singletons.
