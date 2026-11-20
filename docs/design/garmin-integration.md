# Garmin integration — API review and design

Status: research and proposal (ADR-0022, *Proposed*). Date: 2026-11-20.

This document answers four questions before any Garmin code is written: which Garmin APIs exist, what each one
gives and lacks, how stable each one is, and how Overreach should use them without breaking its rules (no backend,
data on device, every metric optional, explainable recommendations).

> **Verification status (2026-11-20).** Section 2 is checked against Garmin's primary sources: the **official
> OpenAPI document** behind `developer.garmin.com/gc-developer-program/personal/swagger-docs/` ("Garmin Connect
> Personal API" 1.0.0, 28 endpoints), the official Personal API FAQ and page, and the official client
> [`garmin/connect-personal-api-python`](https://github.com/garmin/connect-personal-api-python) (Apache-2.0, last
> commit 2026-11-19). Still open, needing a real key: the text of the Terms and Conditions accepted when the key is
> created (behind the Garmin Connect login), rate limits, historical depth, and anonymised fixtures (plan step 0).

## 1. The landscape in November 2026

Garmin data reaches an app in five ways:

| # | Route | Who can use it | Delivery | Needs a server | Stability |
|---|---|---|---|---|---|
| A | **Apple Health** (Garmin Connect writes to it) | Anyone | HealthKit on device | No | High (already used) |
| B | **Connect Developer Program — Personal API key** | Any Garmin user, self-service | Pull, REST, read-only | No | High (official, Garmin-maintained client) |
| C | **Connect Developer Program — Starter / Enterprise** | Approved businesses | Push webhooks (Starter); push, ping/pull and backfill (Enterprise) | **Yes** | High |
| D | **Unofficial Connect API** (`connectapi.garmin.com`, what the Garmin Connect app uses) | Anyone with a login | Pull, REST | No | **Low** |
| E | **Connect IQ** app on the watch | Anyone (SDK) | On the watch, data synced via phone | No | Medium, large effort |

ADR-0005 chose D in November 2026. Since then two things changed the picture:

1. **The unofficial route broke repeatedly in 2026** (section 3).
2. **On 2026-10-21 Garmin reopened its developer program with a free, self-service Personal tier** (route B).
   It did not exist when ADR-0005 was written.

## 2. Route B — the official Personal API

The key finding: **the Personal API is the same family of Connect service endpoints that the Garmin Connect app
uses** (`hrv-service`, `sleep-service`, `usersummary-service`, …), served on a separate host with an official,
documented key → token flow. It is not the partner Health API (`dailies`, `sleeps`, … pushed to a server). So it has
almost all of the data that the unofficial route has, without the login problems.

### Access and auth (verified: official FAQ and client)

- The user creates a key at Garmin Connect web → Settings → Personal API (`connect.garmin.com/app/settings/personalApiToken`),
  accepts the terms, and picks an expiry: **30, 90 or 180 days, or 1 year**. The key is **shown only once**. Garmin
  emails about a week before expiry. Deleting the key revokes it and every token issued from it.
- **Token exchange:** `POST https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token`
  with headers `Authorization: ApiKey <key>` and `Accept: */*`, and no body. The response body *is* the access
  token: a JWT whose expiry is its `exp` claim. It is **valid 24 h** or until the key expires. **There are no refresh
  tokens**: mint a new one with the key.
- **Data calls:** `GET https://personal.connectapi.garmin.com/<path>` with `Authorization: Bearer <jwt>`. Dates are
  `yyyy-MM-dd` and ranges are inclusive.
- The official client re-mints the token when less than 1 h remains, and has a 30 s timeout. It does **not** retry on
  401, 429 or 5xx: every non-2xx is an `HttpError(status_code, method, url, response_text)`. Its README says
  an app "with its own secret store" can pass its own key, which is what the Keychain is for.

### Endpoints (verified: official OpenAPI document)

Servers: `https://personal.connectapi.garmin.com` (and `personal.connectapi.garmin.cn` for China). All `GET`; dates
`yyyy-MM-dd`, ranges inclusive. Limits in quotes are from Garmin's own descriptions.

| Data | Path | Range per request |
|---|---|---|
| Daily summaries (v2) | `/usersummary-service/v2/dailysummaries?startDate&endDate` | "up to a maximum of 1 year" |
| Daily summary (v1, flat) | `/usersummary-service/usersummary/daily?calendarDate` | one day |
| Sleep, one night | `/sleep-service/sleep/dailySleep?date` | one day |
| Sleep, range | `/sleep-service/sleep/dailySleepSummariesByDate?startDate&endDate` | "up to a maximum of 31 days" |
| HRV, one night (+ readings) | `/hrv-service/hrv/{calendarDate}` (204 = no data) | one day |
| HRV, range | `/hrv-service/hrv/daily/{fromDate}/{toDate}` (204 = no data) | not stated (365 d reported) |
| Body Battery | `/wellness-service/wellness/bodyBattery/reports/daily?startDate&endDate[&chunks]` | "up to a maximum of 31 days" |
| Stress | `/usersummary-service/stats/stress/daily/{startDate}/{endDate}` | "up to a maximum of 28 days" |
| Steps | `/usersummary-service/stats/steps/daily/{startDate}/{endDate}` | "up to a maximum of 28 days" |
| Hydration | `/usersummary-service/stats/hydration/daily/{startDate}/{endDate}` | "up to a maximum of 31 days" |
| Heart rate, one day | `/wellness-service/wellness/dailyHeartRate?date` | one day |
| SpO2 | `/wellness-service/wellness/daily/spo2acclimation/{calendarDate}` | one day |
| VO2max | `/metrics-service/metrics/maxmet/daily/{startDate}/{endDate}[?sport=RUNNING…]` | not stated |
| Fitness age | `/fitnessage-service/fitnessage/v2/{calendarDate}` | — |
| HR zones | `/biometric-service/heartRateZones/v2` | — |
| Menstrual cycle | `/periodichealth-service/menstrualcycle/summary/{calendarDate}`, `…/dayview/{calendarDate}?todayDate` | one day |
| Weight | `/weight-service/weight/range/{startDate}/{endDate}`, `/weight-service/weight/all/…` | `all`: "up to a maximum of 364 days" |
| Nutrition | `/nutrition-service/food/logs/{date}` | one day |
| Activities | `/activitylist-service/activities/search/activities?start&limit&startDate&endDate&activityType…` | `limit` default 99 (500s reported above ~45) |
| Activity detail / workouts | `/activity-service/activity/{activityId}`, `…/{activityId}/workouts` | — |
| Wellness activities | `/wellnessactivity-service/activity/summary/range/{fromDate}/{untilDate}` | not stated |
| Original FIT file | `/download-service/files/activity/{activityId}` (`application/x-zip-compressed`) | — |
| Activity types, profile | `/activity-service/activity/activityTypes/simple`, `/userprofile-service/userprofile/settings` | — |

Documented errors are 400, 401, 403, 404 and 500. The spec documents **no rate limit and no 429**; about 100
requests per minute is reported unofficially (`gcpapi-sync`). Garmin says nothing about historical depth.

### What it gives, mapped to `DailyMetrics` (field names from the official OpenAPI schemas)

| Overreach field | Garmin JSON | Notes |
|---|---|---|
| `hrvNightlyAverageMs` | HRV `hrvSummary.lastNightAvg` | **The key gap Health leaves.** Nightly RMSSD. |
| `hrvNightlyHighMs` | `hrvSummary.lastNight5MinHigh` | |
| `hrvBaselineLowMs` / `HighMs` | `hrvSummary.baseline.balancedLow` / `.balancedUpper` (also `lowUpper`, `markerValue`) | **Available** (earlier press reports said it was not). |
| `hrvStatus` | `hrvSummary.status` | `BALANCED`, `UNBALANCED`, `LOW`, `POOR`, `NONE`, `INVALID`. Also `weeklyAvg`, `feedbackPhrase`. |
| `restingHeartRate` | Daily summary `heartRate.restingValue` | Also in Health. |
| `steps` | `movement.steps.value` | Also in Health. |
| `averageStress` | `stress.avgLevel` (0–100) | Garmin-only. |
| `bodyBatteryHigh` / `Low` | `bodyBattery.maxValue` / `.minValue` (v2); `bodyBatteryHighestValue` / `LowestValue` (v1) | Garmin-only, proprietary. Also charged, drained, end-of-day, at wake time. |
| `respirationRate` | `respiration.avgValue`, or sleep `averageRespirationValue` | |
| `spo2Average` | `pulseOx.avgValue`, or sleep `averageSpO2Value` | |
| `sleepSeconds` and stages | Sleep `sleepTimeSeconds`, `deepSleepSeconds`, `lightSleepSeconds`, `remSleepSeconds`, `awakeSleepSeconds` | Day = `calendarDate` (the morning the sleep ended). |
| `sleepScore` | `sleepScores.overall.value` (0–100) | Health has no score. |
| `vo2Max` | `maxmet`: `generic` / `cycling` / `rowing` → `{calendarDate, vo2MaxValue, vo2MaxPreciseValue}`; also `vO2MaxValue` per activity | **Available.** Running VO2max is `generic`. |
| `RunActivity` | `activityId`, `startTimeGMT`, `duration`, `distance`, `averageHR`, `maxHR`, `elevationGain`, `averageRunningCadenceInStepsPerMinute`, `activityType.typeKey` | |
| `RunActivity.trainingLoad` | `activityTrainingLoad` (per activity) | **Garmin load per activity is available.** |
| `aerobic` / `anaerobicTrainingEffect` | `aerobicTrainingEffect`, `anaerobicTrainingEffect` | Per activity. |
| Menstrual cycle | `periodichealth-service` | Optional extra source for ADR-0009. |
| `trainingReadiness`, `trainingStatus`, `acuteLoad`, `recoveryTimeHours` | — | **Not available**: not among the 28 endpoints of the official spec. |

So the only things missing are the aggregate proprietary scores. Acute and chronic load can be computed from the
per-activity `activityTrainingLoad`, our own way and with reasons (ADR-0012).

### Live check with a real key (2026-11-20)

One personal key (Forerunner, account with data since September 2026), about 30 requests in a few minutes:

- **Token:** a JWT issued by `https://diauth.garmin.com`, valid exactly 24 h, with scopes `CONNECT_READ`,
  `PERSONAL_API_FITNESS_READ`, `PERSONAL_API_WELLNESS_READ`, `PERSONAL_API_NUTRITION_READ` and `PERSONAL_API_USER_READ`.
- **Endpoints:** every endpoint in the plan returned 200 with data. The menstrual cycle returns **204 with no body** when
  there is no data, as does an HRV range with no nights. The undocumented `metrics-service/metrics/trainingreadiness`
  and `…/trainingstatus` paths return **404 `{"error":"NOT_FOUND"}`**: confirmed not available.
- **Rate limits:** no rate-limit headers (the host is behind Cloudflare) and no 429 at this pace. Still undocumented.
- **Ranges:** daily summaries v2 accepted 365 days and returned **400 `{}`** at 400 days. HRV accepted 366 days.
  Sleep accepted 32 days although 31 is documented; we keep to the documented limits.
- **History:** every range back to the first day on the account came back. Ranges before it (2019, 2022) return
  empty (`204` or `"data": []`), not errors. Depth beyond a few months could not be tested with this account.
- **Data quirks** that `GarminImport` must handle:
  - Sleep `sleep…TimestampGMT` and `…Local` are **epoch milliseconds** (integers). `…Local` is local wall time encoded as
    if it were UTC. `calendarDate` is the morning the sleep ended.
  - Activity `startTimeGMT` / `startTimeLocal` are `yyyy-MM-dd HH:mm:ss` **without a zone**. Summary v2 timestamps are
    ISO strings. HRV values are integers (ms).
  - VO2max is **sparse**: there is only an entry on days it changed. The `generic` entry carries `sport` and `subSport`,
    which are not in the spec. `vO2MaxValue` on activities was null.
  - `source` is `"GARMIN"` in summaries v2.
  - **Strength workouts recorded on the watch** come back as `strength_training` activities with `totalSets`,
    `totalReps`, `summarizedExerciseSets` (Garmin exercise categories), heart rate and `activityTrainingLoad`. They
    overlap with sessions logged in Overreach (see open questions).
- **Fixtures:** synthetic fixtures with the exact shape of these responses (same keys, nesting, nulls and enums;
  every number changed, dates shifted, ids, names and locations removed) are in
  `Packages/OverreachCore/Tests/GarminImportTests/Fixtures/`, made with `scripts/garmin-fixtures.py`. No real values
  are in the repository.
- **Recording fixtures from a cloud session:** the network proxy injects a saved key into *every* request to the
  host, which overwrites the `Bearer` header that data calls need (the result is 403). Save the key, mint a token, remove
  the saved key, then call with the token. The iPhone has no such proxy.

### Terms

- Official FAQ, verbatim: the Personal API "allows Garmin customers to securely access their own Garmin Connect data
  using an API. It is intended for developers, hobbyists, data enthusiasts, and individuals who want to build personal
  applications using their own Garmin data." And: "It is **not intended for commercial applications serving multiple
  end users.**" Organisations building for many users are pointed to the business program.
- The key is created only after accepting Terms and Conditions in Garmin Connect. That text sits behind the login
  and could not be read **[verify]**. Other projects quote it as "used only by you … for your own use", with no
  sharing of the key.
- For Overreach today, this fits: open source, non-commercial, each person builds or sideloads their own copy
  (ADR-0021), uses their own key for their own data, and the key never leaves their iPhone (Keychain, direct calls).
- It does **not** fit a public App Store or TestFlight app with many users (phase 4). That needs the business
  program: Starter (route C) with a backend, or written permission from Garmin.

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
- **What only it gives:** Training Readiness, Training Status, Garmin's aggregate acute/chronic load, recovery time
  and race predictions. HRV status and baseline, VO2max and per-activity load are also in the Personal API, which
  uses the same service endpoints.

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
   readiness light (nightly HRV, with Garmin's baseline and status) and adds sleep score, stress, Body Battery,
   SpO2, respiration, VO2max, per-activity training load and training effect, and FIT files.
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

- **Empty is not an error.** 204 with no body and `"data": []` mean no data for those days; 404 means an endpoint is
  gone (drift). 400 means a range that is too long, so split it.
- **Tolerant decoding.** Every field optional, decode per item (one bad record never drops the day), ignore unknown
  keys, accept numbers as int or double. A field that disappears degrades that metric, nothing else.
- **Schema drift detection.** The decoder counts missing expected fields and failed items per sync. Settings shows
  "Garmin changed some data; some values are missing" instead of failing silently. Never crash, never block Today.
- **Spec drift check.** Garmin publishes the OpenAPI document in the Swagger page. A script can extract it and
  compare the paths and fields we decode against a committed list, so a removed or renamed field shows up in CI or
  on demand, not on users' phones.
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
| 0 | Done (2026-11-20): checked against Garmin's official OpenAPI document, FAQ and client, and live with a real key; synthetic fixtures recorded. Still open: the text of the key's Terms and Conditions (owner to read), rate limits (undocumented, none hit). Then accept ADR-0022. | docs |
| 1 | `GarminImport`: DTOs + mapping for the HRV range, sleep range and daily summaries v2 (which carry resting HR, steps, stress, Body Battery, respiration and SpO2), with recorded fixtures and Swift Testing tests. | OverreachCore |
| 2 | `GarminSource`: token provider, HTTP client, `MetricsSource` for daily metrics. Wire in `AppContainer`. | OverreachKit, App |
| 3 | Settings: connect (paste key + expiry), status, last sync, disconnect; localized texts (en, es, gl). | SettingsPresentation, FeatureSettings |
| 4 | Readiness: HRV from Garmin feeds `ReadinessRules` (already source-agnostic); evidence note on Garmin HRV (nightly RMSSD) versus Apple SDNN, which are not comparable, so baselines must be per metric type. | Analytics, `docs/evidence.md` |
| 5 | Activities: summaries → `RunActivity` (with `activityTrainingLoad` and training effect) and walks (`ActivitySource`), dedupe with Health; our own acute/chronic load from per-activity load (evidence first). | Core + Kit |
| 6 | FIT decoding (laps, HR, power) for run load and the AI report. | OverreachCore |
| 7 | Women's health → `CycleSource` (ADR-0009). | Core + Kit |

Steps 1–4 are the shippable unit for phase 2 (v0.2). `ReleaseNotes.all` gets an entry when step 3 lands.

### Open questions

- Strength sessions recorded on the watch overlap with sessions logged in Overreach. Do not import them as workouts:
  match them to the logged session by time and attach Garmin's heart rate and `activityTrainingLoad` to it. If no
  logged session matches, keep the load for ACWR (step 5).

- HRV metric type: Garmin reports nightly RMSSD, while Apple Watch writes SDNN to Health. They must not share a baseline.
  Does `DailyMetrics` need a `hrvMetric` tag, or a separate field? (Decide in step 4, with evidence.)
- Is Body Battery worth showing, given it is a proprietary score? It is cheap to store; it is shown as context and
  never used as a rule input unless evidence supports it.
- Exact rate limits (about 100 per minute reported unofficially). A 60-day backfill is about 6 requests: one daily
  summaries call (up to a year), two sleep calls (31 days), one HRV range, two Body Battery calls, plus activity pages.
- Daily summary v2 versus the separate stress, steps and Body Battery endpoints: v2 covers most fields in one call.
  Use it and fall back to the others only if a field is missing.

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
- **Primary:** Garmin Connect Personal API OpenAPI 3.0.1 document, version 1.0.0 (embedded in
  `developer.garmin.com/gc-developer-program/personal/swagger-docs/`, read 2026-11-20); Garmin Connect Personal API FAQ and
  Personal API page; Garmin, `garmin/connect-personal-api-python` (`README.md`, `src/garmin_personal_api/{auth,constants,client,errors}.py`,
  `examples/`).
- `thomascamminady/gcpapi-sync-python`: models generated from Garmin's OpenAPI document (`models/_generated.py`),
  per-endpoint limits and CHANGELOG (unofficial).
- Still to read with a Garmin account: the Terms and Conditions shown when creating the key.
