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
[History import](docs/import.md) · [Installing without a Mac](docs/install-without-mac.md)

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
    TrainingServices      Application layer: reads sources once, answers shared training questions (ADR-0035)
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
.agents/skills/           Agent skills (see Skills)
```

## Dependency rules (enforced in Package.swift and SwiftLint)

1. `Domain` depends on nothing.
2. `Analytics`, `StrongImport`, `GarminImport`, `Reports` depend only on `Domain` (and `Reports` on `Analytics`).
3. Data modules (`Persistence`, `HealthKitSource`, `GarminSource`, `AIKit`, `LocalAlerts`) depend on `Domain`
   (+ `Reports` for `AIKit`) and implement its protocols.
4. `FeatureX` depends on `XPresentation`, `PresentationKit`, `DesignSystem` and `Domain` (value types only;
   `AIKit` only for Today and Assistant). It imports no `Analytics`, no other feature and no concrete data module.
5. `<X>Presentation` depends on `Domain`, `Analytics`, `TrainingServices` and `PresentationKit`
   (`AssistantPresentation` also on `AIExchange`); never on SwiftUI or another presentation module. It reads
   sources and asks shared training questions through `TrainingServices` (ADR-0035). `DesignSystem` takes display
   values only. `AIExchange` uses `TrainingServices` for the shared daily assessment.
6. `App` is the only place that knows concrete implementations. It builds `AppContainer` and injects
   protocols into features.

A new capability (nutrition, another watch) is a new data module plus a new feature module.

## Before you write code

Read the sections of [CODING_STANDARDS.md](CODING_STANDARDS.md) for what you touch; Presentation, Recommendations,
Stored data and Localization cost the most rework when missed. iPhone flows and navigation follow the
[iPhone UX guide](docs/design/iphone-ux.md). Changing the Today recommendation: start from
[how Today decides](docs/design/today-flow.md).

## Working in parallel

Several agents work at once, each in its own branch or worktree.

- **Next task.** In a fresh checkout of `origin/main`, use `python3 scripts/claim-task.py --next --dry-run` to find
  the next issue in [Priorities](docs/priorities.md). To implement it, run `--next` without `--dry-run` before
  reading code. It opens a draft PR and prints `CLAIMED <task> #<PR> <branch>`. Pass a task link for a named
  task or `--none "<reason>"` for work outside the backlog.
  The oldest claim keeps a task: when `scripts/check-task-claim.py` (in `check-local.py` and CI) says another PR
  claimed it first, close yours and run `--next`. When resuming a feature after a merge, check the previous PR.
  Where `claim-task.py` cannot open the PR (a cloud session without a working `gh`), open a draft PR with the
  GitHub tool whose body starts with `Task: <link>`.
- **Planning work.** Open one issue per task and use GitHub dependencies for blockers. Add ready issues to
  [Priorities](docs/priorities.md), an umbrella for a group of tasks and an ADR for architectural decisions.
- A PR's branch belongs to the session that opened it. To update or merge someone else's PR, ask that session or the
  user; work on your own branch instead.
- ADR numbers: take the highest number on `origin/main` plus one, and re-check after rebasing.
- `CHANGELOG.md` and `*.xcstrings` have merge drivers that `scripts/check-local.py` registers. After resolving a
  String Catalog conflict by hand, run `python3 scripts/check-localization.py --fix`.
- Commits and PR titles use Conventional Commits with a scope, as in `feat(plan): …` or `fix(history): …`.
- For implementation requests, open a PR and merge it after its checks pass when the user asked for the merge or the
  session allows it; otherwise report the green PR and wait.
- One task per session: once its PR merges, end with the summary and leave the next task to a new session. Every
  call re-reads the whole conversation, so a long one makes each step dearer; for the same reason, send long output
  (full test runs, builds, logs) to a file and read only the failures.

## Commands

Before opening or updating a PR, run `python3 scripts/check-local.py` (Windows: `py -3 scripts/check-local.py`). It
checks what the diff against `origin/main` touches and prints a log path; without Docker it checks line length only.
CI also runs the Apple packages and the simulator build; read its failures with `scripts/ci-failures.py`, not the
raw logs.

```bash
python3 scripts/check-local.py [--base origin/<branch>] [--fix-eol]   # local check
python3 scripts/ci-failures.py [PR | run id | URL]     # errors of failed CI jobs, by job (default: HEAD's runs)
python3 scripts/check-repo.py                          # repository rules (ADRs, evidence keys, priorities, skills)
python3 scripts/claim-task.py --next [--dry-run]       # claim the next task or explain the choice without a PR
python3 scripts/check-task-claim.py                    # no older PR claims this branch's task
python3 scripts/check-localization.py [--fix]          # translations; --fix rewrites catalogs in canonical form
python3 scripts/add-strings.py --template | <file> | --prune   # missing keys as JSON; add es+gl; drop unused
python3 scripts/session-usage.py [--days N]            # tokens and estimated cost of each agent session
swift test --package-path Packages/OverreachCore       # pure-Swift core (macOS and Linux)
./scripts/test-core.sh                                 # same in Docker (or scripts/test-core.ps1 on Windows)
swift build --package-path Packages/OverreachKit       # Apple-framework modules (macOS)
swiftlint && swift format lint --recursive Packages App/Sources

# Xcode project (requires: brew install xcodegen)
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig   # once; set your team + bundle id
cd App && xcodegen generate && open Overreach.xcodeproj
```

## Skills

Shared skills live in `.agents/skills/` (Codex) with identical copies in `.claude/skills/` (Claude Code):
review, retro and writing-for-agents. Use writing-for-agents when editing this file.

## Known constraints

- Free Apple ID signing: the app expires after 7 days; iCloud/CloudKit and TestFlight need the paid account.
- Garmin does not write HRV to Apple Health; HRV comes from the official Garmin Connect Personal API with the
  user's own key (`GarminSource`, ADR-0022). Keep it optional and isolated. The key stays in the Keychain and
  never goes into backups, reports or logs. Rate limits are unpublished: throttle and back off.
- iOS background refresh is not guaranteed: sync on app launch/foreground.
- Minimum iOS 18 (ADR-0007).
