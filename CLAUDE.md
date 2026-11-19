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

Full product definition: `docs/product.md`. Evidence register: `docs/evidence.md`. Architecture decisions: `docs/adr/`. Importing history:
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
    AIExchange            Versioned messages exchanged with AI chat apps (ADR-0017, docs/ai-exchange.md)
    Presentation/         Per-feature screen state, intents and texts (ADR-0014). Linux-testable.
      PresentationKit     Display names, search, L10n
      <X>Presentation     @Observable models, screen state and intents of feature X
  OverreachKit/           Apple frameworks (SwiftUI, SwiftData, HealthKit, Keychain)
    Persistence           Repositories (in-memory now, SwiftData CloudKit-ready in phase 1)
    HealthKitSource       Apple Health reader/writer
    GarminSource          Unofficial Garmin Connect client (optional, isolated)
    AIKit                 LLMProvider protocol + adapters
    LocalAlerts           Local notifications (rest timer)
    DesignSystem          Colors, spacing, reusable components and charts. No domain types.
    Feature*              SwiftUI views of one screen/flow (Today, Workout, History, Trends,
                          Exercises, Plan, Assistant, Settings, Onboarding). UI only (ADR-0014).
docs/                     Product definition and ADRs
```

## Dependency rules (enforced in Package.swift and SwiftLint — do not break them)

1. `Domain` depends on nothing.
2. `Analytics`, `StrongImport`, `Reports` depend only on `Domain` (and `Reports` on `Analytics`).
3. Data modules (`Persistence`, `HealthKitSource`, `GarminSource`, `AIKit`, `LocalAlerts`) depend on `Domain`
   (+ `Reports` for `AIKit`) and implement its protocols.
4. `FeatureX` depends on `XPresentation`, `PresentationKit`, `DesignSystem` and `Domain` (value types only;
   `AIKit` only for Today and Assistant). **It never imports `Analytics`, another feature or a concrete data
   module.** SwiftPM exposes transitive modules, so SwiftLint fails the build on `import Analytics` in UI code.
5. `<X>Presentation` depends on `Domain`, `Analytics` and `PresentationKit` (`AssistantPresentation` also on
   `AIExchange`); never on SwiftUI or another presentation module. `DesignSystem` depends on nothing of ours:
   it takes display values.
6. `App` is the only place that knows concrete implementations. It builds `AppContainer` and injects
   protocols into features.

Adding a capability (nutrition, another watch) = a new data module + a new feature module. Do not grow
existing modules to do it.

## Conventions

- Swift 6, strict concurrency. Domain types are `Sendable` value types; repositories are actors or
  `Sendable` protocols with `async` APIs.
- UI: SwiftUI + `@Observable` models (`@MainActor`), no third-party architecture frameworks (ADR-0003).
- **Views only render (ADR-0014).** `XModel` and its screen state live in `XPresentation` (OverreachCore);
  `XView` in `FeatureX` renders state and calls intents. Views keep layout, styling, accessibility, static
  copy and purely visual `@State` (sheet open, focus) — never rule-based `if`s, computations, `.filter`/`.sorted`
  over data, or texts derived from rules. One model per screen/flow; sub-screens get a model from the parent.
  SwiftLint warns on `.filter`/`.sorted` in views. Presentation tests are the feature's contract: a redesign is
  safe if they pass. Placeholders (Trends, Assistant) get a presentation module when built.
- Dates: daily data is keyed by `CalendarDay` (year/month/day in the user's calendar), never by raw `Date`.
- Units: store SI (kg, meters, seconds, ms for HRV). Convert only in the UI.
- Every metric is optional. Missing data must degrade gracefully, never crash or block.
- Explainability: anything that produces a recommendation returns the reasons with it.
- **Evidence first (ADR-0012).** Any rule that recommends, proposes or evaluates (progression, stalls,
  deloads, readiness, load, cycle, walking, nutrition) is based on the most robust and most recent evidence
  available — search for current meta-analyses, position stands and RCTs before writing it — and on the best
  labelled heuristics where evidence runs out. Record it in `docs/evidence.md` and cite its key in code
  (`EvidenceReference`); reasons carry the evidence level.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`). Pure logic in `OverreachCore` must be
  covered; use realistic fixtures.
- Strings shown to users go through `App/Resources/Localizable.xcstrings` (en, es, gl; ADR-0015). Models use
  `L10n.text` or `L10n.format("Step {1} of {2}", …)`; check with `python3 scripts/check-localization.py`. Code,
  comments and docs in English.
- **Stored data stays readable (ADR-0018).** A new field in any persisted type is optional or decoded with a
  default; anything that would change existing data needs a backup format bump and a migration step.
  `BackupFormatV1Tests` holds a frozen v1 backup: never edit it.
- **Each release adds its highlights** to `ReleaseNotes.all` (OnboardingPresentation): users who update see
  them once in "What's new". New features worth showing to new users also get a page in the first-run tour.
- No secrets in the repo. Signing settings live in `App/Config/Local.xcconfig` (git-ignored).
- Every non-obvious decision gets an ADR (`docs/adr/NNNN-title.md`).

## Commands

```bash
# Pure-Swift core (works on macOS and Linux)
swift test --package-path Packages/OverreachCore

# Same, in Docker (Windows/any machine without Swift; same image as CI)
./scripts/test-core.sh            # or: ./scripts/test-core.ps1 ; extra args go to swift test

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

Logic in `OverreachCore` (including presentation models) can be developed and tested anywhere Swift runs, or
in Docker with `scripts/test-core.*`. The iOS app is
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
