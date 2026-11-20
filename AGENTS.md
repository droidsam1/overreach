# Overreach — guide for agents

This is the shared guide for every coding agent (Codex reads `AGENTS.md`, Claude Code reads it through
`CLAUDE.md`). Keep it a map: rules live in [CODING_STANDARDS.md](CODING_STANDARDS.md), mechanical rules live in
checks.

## What Overreach is

Overreach (*push smart, recover smarter*) is an open-source iOS app for hybrid athletes (strength + running).
It replaces a gym logger like Strong, pulls recovery data from Apple Health and Garmin Connect, and turns
all of it into daily, explainable training recommendations ("Should I train today? How hard? Run or lift?").

- One user per install. No backend, no accounts. Data, credentials and API keys stay on the device.
- Recommendations come from a deterministic rules engine (`Analytics`). AI only interprets numbers the app
  has already computed.
- The Assistant shares training context and imports plans. See [AI exchange](docs/ai-exchange.md).
- Not a medical device. Never present output as a diagnosis.

[Product and roadmap](docs/product.md) · [Evidence](docs/evidence.md) · [ADRs](docs/adr/) ·
[History import](docs/import.md) · [Installing without a Mac](docs/install-without-mac.md) ·
[iPhone UX guide](docs/design/iphone-ux.md)

## Repository layout

```
App/                      iOS app target (generated with XcodeGen from App/project.yml)
  Sources/                Composition root: OverreachApp, AppContainer, RootView
  Resources/              Asset catalog, Localizable.xcstrings, InfoPlist.xcstrings
  Config/                 Base.xcconfig + Local.xcconfig.example (Local.xcconfig is git-ignored)
  project.yml             XcodeGen spec (Info.plist and entitlements are generated from it)
Packages/
  OverreachCore/          Pure Swift. No Apple-only frameworks. Builds and tests on Linux.
    Domain                Entities + repository/source protocols
    Analytics             Load, progression, fatigue, ACWR, readiness rules (pure functions)
    StrongImport          Strong CSV parsing + exercise → muscle-group mapping
    GarminImport          Garmin Personal API responses → domain values, endpoints, sync plan (ADR-0022)
    Reports               Markdown report for sharing with ChatGPT/Claude
    AIExchange            Versioned messages exchanged with AI chat apps (ADR-0017, docs/ai-exchange.md)
    Presentation/         Per-feature screen state, intents and texts (ADR-0014). Linux-testable.
      PresentationKit     Display names, search, L10n
      <X>Presentation     @Observable models, screen state and intents of feature X
  OverreachKit/           Apple frameworks (SwiftUI, SwiftData, HealthKit, Keychain)
    Persistence           SwiftData repositories, device-local drafts and portable backups (ADR-0004/0018)
    HealthKitSource       Apple Health reader/writer
    GarminSource          Garmin Connect Personal API client (optional, isolated; ADR-0022)
    AIKit                 LLMProvider protocol + adapters
    LocalAlerts           Local notifications (rest timer, Garmin key expiry reminder)
    DesignSystem          Colors, spacing, reusable components and charts. No domain types.
    Feature*              SwiftUI views of one screen/flow (Today, Workout, History, Trends,
                          Exercises, Plan, Assistant, Settings, Onboarding). UI only (ADR-0014).
docs/                     Product definition, design notes, evidence register and ADRs
scripts/                  Local checks, merge drivers and test helpers
.agents/skills/           Shared agent skills; .claude/skills/ holds identical copies for Claude Code
```

## Dependency rules (enforced in Package.swift and SwiftLint)

1. `Domain` depends on nothing.
2. `Analytics`, `StrongImport`, `GarminImport`, `Reports` depend only on `Domain` (and `Reports` on `Analytics`).
3. Data modules (`Persistence`, `HealthKitSource`, `GarminSource`, `AIKit`, `LocalAlerts`) depend on `Domain`
   (+ `Reports` for `AIKit`) and implement its protocols.
4. `FeatureX` depends on `XPresentation`, `PresentationKit`, `DesignSystem` and `Domain` (value types only;
   `AIKit` only for Today and Assistant). It imports no `Analytics`, no other feature and no concrete data module.
5. `<X>Presentation` depends on `Domain`, `Analytics` and `PresentationKit` (`AssistantPresentation` also on
   `AIExchange`); never on SwiftUI or another presentation module. `DesignSystem` takes display values only.
6. `App` is the only place that knows concrete implementations. It builds `AppContainer` and injects
   protocols into features.

A new capability (nutrition, another watch) is a new data module plus a new feature module.

## Before you write code

Read the sections of [CODING_STANDARDS.md](CODING_STANDARDS.md) for what you touch. The ones that cost the most
rework when missed:

- Views only render; logic and texts live in the presentation model ([Presentation](CODING_STANDARDS.md#presentation-adr-0014)).
- Recommendation rules start from current evidence in `docs/evidence.md` ([Recommendations](CODING_STANDARDS.md#recommendations-adr-0012)).
- Persisted types stay readable by older backups ([Stored data](CODING_STANDARDS.md#stored-data-adr-0018)).
- User-facing strings go through the String Catalog in en, es and gl ([Localization](CODING_STANDARDS.md#localization-adr-0015)).

## Working in parallel

Several agents work at once, each in its own branch or worktree.

- Start from a fresh `origin/main`. When resuming a feature after a merge, check the previous PR and continue from
  the [hybrid planning backlog](docs/design/readiness-and-hybrid-planning.md#continue-from-here).
- ADR numbers: take the highest number on `origin/main` plus one, and re-check after rebasing. `check-repo.py`
  fails on duplicates.
- `CHANGELOG.md` merges with git's union driver; `*.xcstrings` merges per key with `scripts/merge-xcstrings.py`,
  which `scripts/check-local.py` registers in the repository's git config.
- After resolving a String Catalog conflict by hand, run `python3 scripts/check-localization.py --fix`.
- Commits and PR titles use Conventional Commits with a scope, as in `feat(plan): …` or `fix(history): …`.

## Commands

Before opening or updating a PR, run the compact local check: `python3 scripts/check-local.py`
(Windows: `py -3 scripts/check-local.py`). It runs the repository rules, then picks translations, SwiftLint
(no new warnings on changed lines) and the core tests from the diff against `origin/main` (`--base origin/<branch>`
for another base), and prints a log path. CI runs the same rules plus the Apple packages and the simulator build;
read its failures with `scripts/ci-failures.py`, not the raw logs.

```bash
python3 scripts/check-local.py [--fix-eol]             # local check; --fix-eol rewrites CRLF working copies as LF
python3 scripts/ci-failures.py [PR | run id | URL]     # errors of failed CI runs, by job (default: HEAD's runs)
python3 scripts/check-repo.py                         # ADRs, frozen backup fixture, release notes, skills, links
python3 scripts/check-localization.py [--fix]          # translations; --fix rewrites catalogs in canonical form
python3 scripts/add-strings.py --template | <file> | --prune   # missing keys as JSON; add es+gl; drop unused
swift test --package-path Packages/OverreachCore       # pure-Swift core (macOS and Linux)
./scripts/test-core.sh                                 # same in Docker (or scripts/test-core.ps1 on Windows)
swift build --package-path Packages/OverreachKit       # Apple-framework modules (macOS)
swiftlint && swift format lint --recursive Packages App/Sources

# Xcode project (requires: brew install xcodegen)
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig   # once; set your team + bundle id
cd App && xcodegen generate && open Overreach.xcodeproj
```

## Skills

Shared skills live in `.agents/skills/` (Codex) with identical copies in `.claude/skills/` (Claude Code);
`check-repo.py` keeps them in sync.

- **review** — review a diff or PR against the coding standards.
- **retro** — retrospective of agent sessions that proposes guide, check and tooling changes. Run when asked.
- **writing-for-agents** — style for anything agents read: this file, `CODING_STANDARDS.md`, skills and docs.

## Known constraints

- Free Apple ID signing: the app expires after 7 days; iCloud/CloudKit and TestFlight need the paid account.
- Garmin does not write HRV to Apple Health; HRV comes from the official Garmin Connect Personal API with the
  user's own key (`GarminSource`, ADR-0022). Keep it optional and isolated. The key stays in the Keychain and
  never goes into backups, reports or logs. Rate limits are unpublished: throttle and back off.
- iOS background refresh is not guaranteed: sync on app launch/foreground.
- Minimum iOS 18 (ADR-0007).
- UI work without a Mac has no simulator or previews: keep views thin so logic is testable in `OverreachCore`.
