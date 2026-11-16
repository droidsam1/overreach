# CLAUDE.md — Overreach

Guidance for Claude (and humans) working in this repository. Read this first in every session.

## What Overreach is

Overreach (*push smart, recover smarter*) is an open-source iOS app for hybrid athletes (strength + running).
It replaces a gym logger like Strong, pulls recovery data from Apple Health and Garmin Connect, and turns
all of it into daily, explainable training recommendations ("Should I train today? How hard? Run or lift?").

- One user per install. No backend, no accounts. Data, credentials and API keys stay on the device.
- Recommendations come from a deterministic rules engine (`Analytics`). AI only interprets numbers the app
  has already computed.
- AI access: prototype = share a Markdown report to the ChatGPT/Claude app; later = in-app chat through a
  provider-agnostic `LLMProvider` (OpenAI default, Anthropic, any OpenAI-compatible API).
- Not a medical device. Never present output as a diagnosis.

Full product definition: `docs/product.md`. Architecture decisions: `docs/adr/`. Importing history:
`docs/import.md` (ADR-0011).

## Repository layout

```
App/                      iOS app target (generated with XcodeGen from App/project.yml)
  Sources/                Composition root: OverreachApp, AppContainer, RootView
  Resources/              Asset catalog
  Config/                 Base.xcconfig + Local.xcconfig.example (Local.xcconfig is git-ignored)
  project.yml             XcodeGen spec (Info.plist and entitlements are generated from it)
Packages/
  OverreachCore/          Pure Swift. No Apple-only frameworks. Builds and tests on Linux.
    Domain                Entities + repository/source protocols
    Analytics             Load, progression, fatigue, ACWR, readiness rules (pure functions)
    StrongImport          Strong CSV parsing + exercise → muscle-group mapping
    Reports               Markdown report for sharing with ChatGPT/Claude
  OverreachKit/           Apple frameworks (SwiftUI, SwiftData, HealthKit, Keychain)
    Persistence           Repositories (in-memory now, SwiftData CloudKit-ready in phase 1)
    HealthKitSource       Apple Health reader/writer
    GarminSource          Unofficial Garmin Connect client (optional, isolated)
    AIKit                 LLMProvider protocol + adapters
    DesignSystem          Colors, spacing, reusable components and charts
    Feature*              One module per screen/flow (Today, Workout, History, Trends,
                          Exercises, Plan, Assistant, Settings, Onboarding)
docs/                     Product definition and ADRs
```

## Dependency rules (enforced in Package.swift — do not break them)

1. `Domain` depends on nothing.
2. `Analytics`, `StrongImport`, `Reports` depend only on `Domain` (and `Reports` on `Analytics`).
3. Data modules (`Persistence`, `HealthKitSource`, `GarminSource`, `AIKit`) depend on `Domain`
   (+ `Reports` for `AIKit`) and implement its protocols.
4. `Feature*` modules depend on `Domain`, `Analytics`, `DesignSystem` (and `AIKit` only for Today and
   Assistant). **A feature never imports another feature or a concrete data module.**
5. `App` is the only place that knows concrete implementations. It builds `AppContainer` and injects
   protocols into features.

Adding a capability (nutrition, another watch) = a new data module + a new feature module. Do not grow
existing modules to do it.

## Conventions

- Swift 6, strict concurrency. Domain types are `Sendable` value types; repositories are actors or
  `Sendable` protocols with `async` APIs.
- UI: SwiftUI + `@Observable` models (`@MainActor`), no third-party architecture frameworks (ADR-0003).
  Pattern per feature: `XView` (SwiftUI) + `XModel` (`@Observable`, holds state, calls use cases).
- Dates: daily data is keyed by `CalendarDay` (year/month/day in the user's calendar), never by raw `Date`.
- Units: store SI (kg, meters, seconds, ms for HRV). Convert only in the UI.
- Every metric is optional. Missing data must degrade gracefully, never crash or block.
- Explainability: anything that produces a recommendation returns the reasons with it.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`). Pure logic in `OverreachCore` must be
  covered; use realistic fixtures.
- Strings shown to users go through String Catalogs (es, en). Code, comments and docs in English.
- No secrets in the repo. Signing settings live in `App/Config/Local.xcconfig` (git-ignored).
- Every non-obvious decision gets an ADR (`docs/adr/NNNN-title.md`).

## Commands

```bash
# Pure-Swift core (works on macOS and Linux)
swift test --package-path Packages/OverreachCore

# Apple-framework modules (macOS)
swift build --package-path Packages/OverreachKit

# Generate and open the Xcode project (requires: brew install xcodegen)
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig   # once; set your team + bundle id
cd App && xcodegen generate && open Overreach.xcodeproj

# Lint / format
swiftlint
swift format lint --recursive Packages App/Sources
```

## Building without a Mac

Logic in `OverreachCore` can be developed and tested anywhere Swift runs (Linux, Windows). The iOS app is
built by the **Build IPA** workflow (`.github/workflows/ipa.yml`) on every push to `main`; the artifact is
sideloaded with Sideloadly/AltStore (`docs/install-without-mac.md`). UI work without a Mac has no simulator
or previews, so keep views thin and push logic into models and `OverreachCore` where it can be tested.

## Roadmap (current phase in bold)

- **Phase 0 — Foundation:** repo, modules, CI, DesignSystem basics, domain model, docs. ← current
- Phase 1 (v0.1) — Replace Strong: exercise catalog, routines, live logger, history, e1RM/PRs, Strong CSV
  import, write workouts to Health, JSON backup to an iCloud Drive folder, and the **progression engine**:
  next-session targets from history, stall detection with suggestions, deload proposals from training
  signals (`docs/design/progression-engine.md`).
- Phase 2 (v0.2) — Recovery: Health + Garmin sync, daily check-in, Today screen, readiness traffic light;
  deload proposals also use HRV, resting HR, sleep, stress and sickness; cycle phase as context with
  phase-aware baselines (ADR-0009, `docs/design/cycle-aware-training.md`); steps and walks vs baseline as
  low-weight load and recovery tool (ADR-0010, `docs/design/daily-activity.md`).
- Phase 3 — Intelligence: plan, load/progression analysis, recommendations, shareable report, Trends.
- Phase 4 — Validation & distribution: paid Apple Developer account, CloudKit sync, TestFlight,
  in-app chat via API.

Phases 1–3 are the prototype. Keep each phase shippable.

## Known constraints

- Free Apple ID signing: the app expires after 7 days; iCloud/CloudKit and TestFlight need the paid account.
  Verify early that HealthKit signs correctly with a personal team.
- Garmin does not write HRV to Apple Health; HRV comes from the unofficial Garmin Connect API
  (`GarminSource`). Keep it optional and isolated; it can break when Garmin changes things (ADR-0005).
- iOS background refresh is not guaranteed: sync on app launch/foreground.
- Minimum iOS 18 (ADR-0007).
