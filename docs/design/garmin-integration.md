# Garmin integration — API review and design

Status: research and proposal (ADR-0022, *Proposed*). Date: 2026-11-20.

This document answers four questions before any Garmin code is written: which Garmin APIs exist, what each one
gives and lacks, how stable each one is, and how Overreach should use them without breaking its rules (no backend,
data on device, every metric optional, explainable recommendations).

> **Verification status.** Garmin's own developer site (`developer.garmin.com`) could not be read from the
> environment where this was written, so the facts below come from press coverage of the October 2026 launch,
> the changelogs and issue trackers of open-source clients, and partner integrations. Items marked **[verify]**
> must be checked against the official Personal API reference (Swagger) and Supplemental Terms before
> implementation starts. That check is step 0 of the plan.

## 1. The landscape in November 2026

Garmin data reaches an app in five ways:

| # | Route | Who can use it | Delivery | Needs a server | Stability |
|---|---|---|---|---|---|
| A | **Apple Health** (Garmin Connect writes to it) | Anyone | HealthKit on device | No | High (already used) |
| B | **Connect Developer Program — Personal API key** | Any Garmin user, self-service | Pull, REST, read-only | No | High (official, documented) |
| C | **Connect Developer Program — Starter / Enterprise** | Approved businesses | Push webhooks (Starter); push, ping/pull and backfill (Enterprise) | **Yes** | High |
| D | **Unofficial Connect API** (`connectapi.garmin.com`, what the Garmin Connect app uses) | Anyone with a login | Pull, REST | No | **Low** |
| E | **Connect IQ** app on the watch | Anyone (SDK) | On the watch, data synced via phone | No | Medium, large effort |

ADR-0005 chose D in November 2026. Since then two things changed the picture:

1. **The unofficial route broke repeatedly in 2026** (section 3).
2. **On 2026-10-21 Garmin reopened its developer program with a free, self-service Personal tier** (route B).
   It did not exist when ADR-0005 was written.

## 2. Route B — the official Personal API

What is known from launch coverage (DC Rainmaker, the5krunner, Garmin Rumors, Tredict) and early adopters:

- **Access:** the user creates a key in Garmin Connect settings, with no application or review. It is free.
- **Key lifetime:** the user picks 30, 90 or 180 days, or 1 year. Garmin emails before it expires. The key is shown
  only once.
- **Auth:** the key is not sent on data calls. It is exchanged for an **OAuth2 access token valid 24 h** (or until
  the key expires). There are reportedly no refresh tokens: mint a new token from the key. The token endpoint is on
  Garmin's Personal API host **[verify exact URL and request format]**.
- **Delivery:** pull only, read-only (about 26 read endpoints reported **[verify list]**). No Training or Courses
  API: it cannot send workouts to the watch.
- **Data:** activity summaries (JSON) plus the original **.FIT file** of each activity; health summaries (JSON);
  women's health summaries (JSON).
- **Rate limits and query windows:** not found in any secondary source **[verify]**. The partner Health API caps
  windows at 24 h per request for most summaries, so design for per-day requests until confirmed.
- **Historical depth:** FIT files reportedly "of any age"; depth of health summaries **[verify]**.

### What it reportedly gives (mapped to `DailyMetrics`)

Health summary types follow the partner Health API (`dailies`, `epochs`, `sleeps`, `stressDetails`, `hrv`,
`pulseOx`, `allDayRespiration`, `userMetrics`, `bodyComps`, `bloodPressures`, `skinTemp`, women's health)
**[verify which are in the Personal tier]**.

| Overreach field | Garmin source (expected) | Notes |
|---|---|---|
| `hrvNightlyAverageMs` | `hrv.lastNightAvg` | **The key gap Health leaves.** Confirmed working by DC Rainmaker. |
| `hrvNightlyHighMs` | `hrv.lastNight5MinHigh` | |
| 7-day HRV average | `hrv.weeklyAvg` | Not stored today; we compute our own 7-day ln average anyway (ADR-0020). |
| `hrvStatus`, `hrvBaselineLow/HighMs` | — | Reported missing **[verify]**. Not needed: ADR-0020 uses our own baseline. |
| `restingHeartRate` | `dailies.restingHeartRateInBeatsPerMinute` | Also in Health. |
| `steps` | `dailies.steps` | Also in Health. |
| `averageStress` | `dailies.averageStressLevel` | Garmin-only. |
| `bodyBatteryHigh/Low` | Derived from `stressDetails` body battery samples (`dailies` has no high/low) | Garmin-only, proprietary score. |
| `respirationRate` | `allDayRespiration` / `sleeps` | |
| `spo2Average` | `pulseOx` | |
| sleep stages, `sleepScore` | `sleeps` (deep, light, REM, awake, score) | Health has stages but no score. |
| `vo2Max` | `userMetrics.vo2Max` | Press reports it as stripped or 404 **[verify]**. |
| `trainingReadiness`, `trainingStatus`, `acuteLoad`, `recoveryTimeHours` | — | **Not available** (404 or stripped, per DC Rainmaker and early adopters). |
| `RunActivity` (+ HR, cadence, elevation, training effect) | Activity summary + FIT | Also in Health (without training effect). |
| Menstrual cycle | Women's health summaries | Optional extra source for ADR-0009. |

### Terms (the open question)

The Supplemental Terms reportedly say a personal key "may be used only by you in connection with applications,
services, or tools that you develop or operate for your own use" and must not be shared with third parties
**[verify the exact text]**. For Overreach:

- The key never leaves the device (Keychain, direct calls from the iPhone): it is not shared with us or anyone else.
- Overreach is open source and today each user builds or sideloads their own copy (ADR-0021, `install-without-mac.md`).
  That reads as "a tool that you operate for your own use". It is the best fit of any route.
- A future App Store or TestFlight distribution (phase 4) is a grey area: other projects read the terms as
  forbidding a published app built on users' personal keys. **Before phase 4, ask Garmin in writing**, or move to
  Starter (route C) with a backend.

## 3. Route D — the unofficial Connect API: what happened in 2026

Timeline from `matin/garth`, `cyberjunky/python-garminconnect` (issues #332, #337, #369 and its changelog):

- **2026-03-17/19:** logins start failing with 401 and 429 on `connectapi.garmin.com/oauth-service/oauth/preauthorized`.
  Garmin changed the auth flow, breaking the mobile OAuth1→OAuth2 approach the whole ecosystem relied on.
- **Late March 2026:** `garth`, the auth library used by almost every client, is **deprecated**: new logins no
  longer work.
- **April 2026:** Cloudflare blocks the old mobile User-Agent; clients fall back to TLS fingerprint impersonation
  (`curl_cffi`), five login strategies, and 30–45 s random delays before posting credentials. Garminconnect 0.3.0
  drops garth; 0.3.2 works again.
- **April–May 2026:** 429s come back for some users; Garmin can block by client fingerprint, not only by IP.
- **June 2026:** freshly refreshed tokens rejected with "Token is not active" (#369). Closed in July without a
  confirmed root cause.
- **August–October 2026:** eleven releases (0.3.10 → 0.3.20). 0.3.20 (2026-10-23): mobile login "works again
  instead of always returning 429", and HTTP 427 is now treated as 429.

Current flow (python-garminconnect 0.3.x): credentials to `sso.garmin.com/mobile/api/login` with the Garmin
Connect iOS client id, ticket exchanged at `diauth.garmin.com` for access + refresh tokens, refresh before each
call, full login (possibly MFA) when the refresh token dies. Token lifetimes are not documented.

**Assessment for Overreach:**

- **Fragility:** one serious break every 1–2 months in 2026, each needing reverse engineering. A Python library
  with an active maintainer and hundreds of users absorbed it; a Swift port maintained by this project would trail
  every fix, and a sideloaded app that expires every 7 days cannot ship fixes quickly.
- **Security:** the app would handle the user's Garmin **password** and MFA, and impersonate Garmin's own app
  (client id, user agent, TLS fingerprint).
- **Terms:** clearly against Garmin's terms, and now there is an official alternative.
- **What only it gives:** Training Readiness, Training Status, acute/chronic load, recovery time, HRV status and
  baseline, race predictions, VO2max.

Those Garmin-only scores are **proprietary black boxes**. Overreach's rules (ADR-0012, ADR-0020) explain every
recommendation from raw signals measured against the person's own baseline. A Garmin "readiness 34" is not
explainable and would duplicate what `ReadinessRules` computes. Showing them is nice to have, not a requirement.

## 4. Routes C and E

- **Starter (free, up to 1,000 users) / Enterprise (paid from April 2027):** OAuth2 PKCE per user and push webhooks
  to a public HTTPS endpoint; no ping or backfill on Starter. It needs a server, which breaks "no backend"
  (CLAUDE.md, ADR-0004). Revisit in phase 4 only if the app is distributed publicly and the Personal terms rule it
  out. Same data as Personal, plus the Training API (workouts to the watch).
- **Connect IQ:** a watch app could record beat-to-beat intervals and compute HRV itself. Large effort, battery
  cost, separate toolchain. Keep as a plan B in case Garmin closes the Personal tier.

## 5. Decision summary

1. **Primary: Personal API (B)**, behind the existing `MetricsSource`. It fills the one gap that matters for the
   readiness light (nightly HRV) and adds sleep score, stress, Body Battery, SpO2, respiration and FIT files.
2. **Keep Apple Health (A)** as the baseline source. Garmin is an enrichment and the app must work fully without it.
3. **Do not build the unofficial client (D).** Do not port it as a fallback either. If proprietary Garmin scores
   are ever wanted, that is a separate, opt-in, clearly labelled experimental module with its own ADR.
4. **Starter (C)** only in phase 4, if public distribution requires it.

## 6. Architecture

Follow the StrongImport pattern: parsing and mapping are pure and Linux-testable in `OverreachCore`; networking and
the Keychain live in `OverreachKit`.

```
OverreachCore
  GarminImport (new, depends on Domain only)
    DTOs          Decodable mirrors of Garmin JSON. Every field optional, unknown keys ignored.
    Mapping       DTO → DailyMetrics / RunActivity / DailyActivity / MenstrualEvent. Pure functions.
    BodyBattery   High/low from stressDetails samples.
    SyncPlan      Which days to fetch: last synced day, today's re-fetch, gaps, max window. Pure.
    FIT (later)   Minimal FIT decoder for activity files (records, laps, sessions).
OverreachKit
  GarminSource (rewritten)
    GarminTokenProvider   personal key in the Keychain → 24 h access token (cached in memory and Keychain,
                          re-minted on 401 or expiry; never logged)
    GarminHTTPClient      URLSession, timeouts, retry with backoff + jitter on 429/5xx, honours Retry-After,
                          a per-sync request budget, cancellation
    GarminMetricsSource   MetricsSource + ActivitySource + CycleSource on top of the two above
  FeatureSettings / SettingsPresentation: "Garmin" section (paste key, key expiry, last sync, status)
```

`App` decides the source order. `DailyMetrics.merging` is already "first wins": keep `[garmin, healthKit]` so Garmin
values win where both have them (HRV, sleep stages), and Health fills the rest.

### Robustness practices

- **Tolerant decoding.** Every field optional, decode per item (one bad record never drops the day), ignore unknown
  keys, accept numbers as int or double. A field that disappears degrades that metric, nothing else.
- **Schema drift detection.** The decoder counts missing expected fields and failed items per sync. Settings shows
  "Garmin changed some data; some values are missing" instead of failing silently. Never crash, never block Today.
- **Contract tests on real fixtures.** Record one anonymised response per endpoint (several watch models: e.g.
  Forerunner 255 and 265) into `Packages/OverreachCore/Sources/Fixtures`; mapping tests run on Linux in CI. When
  Garmin changes a payload, the fix is a new fixture plus a test.
- **Units at the edge.** Garmin mixes seconds and milliseconds, and local versus GMT timestamps. Convert once in
  `Mapping` to SI and `CalendarDay` (the day the sleep *ended*, in the user's calendar), with tests around DST.
- **Idempotent, incremental sync.** Store the last synced day; on each foreground fetch re-pull today and yesterday
  (late watch syncs) and any gap, up to a window (e.g. 60 days on first connect, enough for the ADR-0020 baselines).
  Upserting a day twice gives the same result.
- **Key lifecycle.** Store the key's expiry date the user picks; a local notification (`LocalAlerts`) and a Settings
  banner 7 days before. On 401 with a fresh token: the key was revoked, so show "Reconnect Garmin".
- **Deduplicate runs.** Garmin also writes runs to Health. Match by start time (±2 min) and duration; keep the
  Garmin record (it has training effect and the FIT file) and drop the Health copy.
- **Secrets.** Key and token only in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), never in
  logs, backups (ADR-0018 backup excludes them) or AI reports.
- **Kill switch.** Disconnecting deletes the key and token; imported values stay (they are the user's data,
  `sources` shows where they came from).
- **Provenance.** `DailyMetrics.sources` already records Garmin; reasons on Today can say "HRV from Garmin".

## 7. Plan

| Step | Content | Where |
|---|---|---|
| 0 | Read the official Personal API Swagger and Supplemental Terms with a real key; confirm endpoints, windows, rate limits, field names, the token exchange, and the terms. Update this document; accept or amend ADR-0022. | docs |
| 1 | `GarminImport`: DTOs + mapping for `hrv`, `sleeps`, `dailies`, `stressDetails`, with recorded fixtures and Swift Testing tests. | OverreachCore |
| 2 | `GarminSource`: token provider, HTTP client, `MetricsSource` for daily metrics. Wire in `AppContainer`. | OverreachKit, App |
| 3 | Settings: connect (paste key + expiry), status, last sync, disconnect; localized texts (en, es, gl). | SettingsPresentation, FeatureSettings |
| 4 | Readiness: HRV from Garmin feeds `ReadinessRules` (already source-agnostic); evidence note on Garmin HRV (nightly RMSSD) versus Apple SDNN, which are not comparable, so baselines must be per metric type. | Analytics, `docs/evidence.md` |
| 5 | Activities: summaries → `RunActivity` and walks (`ActivitySource`), dedupe with Health. | Core + Kit |
| 6 | FIT decoding (laps, HR, power) for run load and the AI report. | OverreachCore |
| 7 | Women's health → `CycleSource` (ADR-0009). | Core + Kit |

Steps 1–4 are the shippable unit for phase 2 (v0.2). `ReleaseNotes.all` gets an entry when step 3 lands.

### Open questions

- HRV metric type: Garmin reports nightly RMSSD, while Apple Watch writes SDNN to Health. They must not share a baseline.
  Does `DailyMetrics` need a `hrvMetric` tag, or a separate field? (Decide in step 4, with evidence.)
- Is Body Battery worth showing, given it is a proprietary score? It is cheap to store; it is shown as context and
  never used as a rule input unless evidence supports it.
- Exact rate limits; if they are tight, first-connect backfill may need to be spread over several launches.

## Sources

- DC Rainmaker, "Garmin Revamps and Opens Up Connect Developer API Program" (Oct 2026).
- the5krunner, "Garmin Personal API Key 2026 — what athletes can and cannot access" (2026-10-22).
- Garmin Rumors, "Garmin Revamps Its Connect Developer API With Personal, Starter, and Enterprise Access".
- Tredict blog, "Garmin Personal API reads your current activities but does not send workouts to your watch".
- `matin/garth` README (deprecation notice).
- `cyberjunky/python-garminconnect`: README, CHANGELOG (0.3.10–0.3.20), `docs/API_ENDPOINTS.md`, issues #332, #337, #369.
- `TokenCemetery/Grada` issue #115 (Personal API terms for published apps); `e2kd7n/ride-optimizer` issue #607.
- Sahha and Momentum blogs on the 2026 tiers and fees; partner integrations (`fiddur/aurboda` #1782/#1784) for
  Health API data types and the Body Battery source.
- To read in step 0: `developer.garmin.com/gc-developer-program/personal/personal-faq/` and `…/personal/swagger-docs/`.
