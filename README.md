# Overreach

**Push smart, recover smarter.**

Overreach is an open-source iOS app for hybrid athletes — people who lift *and* run. It logs your strength
sessions, reads your recovery data (HRV, sleep, resting heart rate, Body Battery, training load…) from
Apple Health and Garmin Connect, and answers the questions you ask every morning:

- Should I train today? How hard?
- Run or lift? How many kilometres, at what intensity?
- How did yesterday's leg day affect today's run?
- Am I actually progressing, or have I stalled?

Every recommendation comes with the reasons behind it. When you want to dig deeper, Overreach packs your
metrics into a report you can hand to ChatGPT or Claude.

> **Status:** early development (phase 0 — foundation). Not usable yet.

## Principles

- **Local-first and private.** No backend, no accounts, no telemetry. Your data, credentials and API keys
  never leave your iPhone unless you share a report.
- **Explainable.** Numbers are computed by a deterministic engine; AI only interprets them.
- **Every source is optional.** No Garmin? Overreach works with Apple Health and a daily check-in.
- **Not medical advice.** Overreach is a training tool, not a medical device.

## Features (planned)

| Area | What it does |
| --- | --- |
| Workout logger | Routines, live sessions (sets, reps, kg, RPE, rest timer), history, PRs, estimated 1RM, Strong CSV import |
| Progression | Next-session targets per exercise (double progression, linear, rep cycles, RPE-based), stall alerts with suggestions, deload proposals from training and recovery signals |
| Recovery | Apple Health + Garmin Connect sync, personal HRV baseline, daily check-in, readiness traffic light |
| Load & progression | Effective sets per muscle group, tonnage, acute:chronic workload, muscle fatigue, progressive-overload tracking, run/lift interference |
| Recommendations | Today's session: weights and reps, or run type, distance and HR zone, adjusted to your plan and recovery |
| AI | Shareable Markdown report for ChatGPT/Claude; later an in-app chat with any LLM provider |

## Architecture

A modular Swift Package Manager setup with strict dependency rules:

- `Packages/OverreachCore` — pure Swift (domain, analytics, Strong import, reports and each screen's state and
  logic). Builds and tests on Linux.
- `Packages/OverreachKit` — Apple frameworks: persistence, HealthKit, Garmin, AI providers, design system,
  and one UI-only module per feature, so screens can be redesigned without touching the logic.
- `App` — the composition root, generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

See [`CLAUDE.md`](CLAUDE.md) for the full map and [`docs/adr`](docs/adr) for the decisions behind it.

## Getting started

Requirements: macOS with Xcode 16+, iOS 18+ device or simulator, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cp App/Config/Local.xcconfig.example App/Config/Local.xcconfig   # set your team id and bundle id prefix
cd App && xcodegen generate && open Overreach.xcodeproj
```

No Mac? Every push to `main` builds an installable `.ipa` on GitHub Actions — see
[`docs/install-without-mac.md`](docs/install-without-mac.md). To try a release, follow the
[tester guide](docs/beta-guide.es.md) (Spanish).

Run the core tests:

```bash
swift test --package-path Packages/OverreachCore
```

## Contributing

Contributions are welcome — read [`CONTRIBUTING.md`](CONTRIBUTING.md) first.

## Disclaimer

Overreach is an independent project. It is not affiliated with, endorsed by or sponsored by Garmin, Strong
or Apple. Garmin Connect integration uses an unofficial API and may stop working at any time.

## License

To be confirmed (GPLv3 is the current proposal).
