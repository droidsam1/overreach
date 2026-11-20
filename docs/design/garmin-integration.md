# Garmin integration — API review and design

Status: accepted (ADR-0022). Date: 2026-11-20.

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
- **Recording fixtures:** do it on your own machine (mint a token with the key, call the endpoints, run
  `scripts/garmin-fixtures.py`, and delete the raw responses). Keeping the key in a hosted service's secrets conflicts
  with the terms (see below), and a cloud network proxy that injects the key into every request to the host also
  overwrites the `Bearer` header that data calls need (403).

### Terms

**Garmin Connect Personal API Supplemental Terms** (last updated 2026-10-01; text read from the key creation page by
the project owner on 2026-11-20). They supplement the Garmin Terms of Use and prevail over them for the API:

1. **Personal use of the key:** "Any API key issued to you is personal to you and may be used only by you in connection
   with applications, services, or tools that you develop or operate for your own use. You may not sell, transfer,
   sublicense, distribute, disclose, or otherwise share your API key with any third party. You are responsible for
   maintaining the confidentiality and security of your API key and for all activity that occurs using your API key."
2. **Rate limits:** "Garmin may establish and enforce limits on the number, frequency, or volume of API requests […]
   These limits may be modified by Garmin at any time. If you exceed applicable rate limits, Garmin may throttle, delay,
   reject, suspend, or otherwise restrict API requests without notice."
3. **Violations:** may lead to suspension or termination of access and revocation of the key, and count as a breach
   of the Garmin Terms of Use.

The official FAQ adds that the Personal API "is not intended for commercial applications serving multiple end users."

What this means for Overreach:

- **Allowed as designed.** Each person runs their own copy (built or sideloaded, ADR-0021) and uses it for their own
  data: a tool "that you operate for your own use". The project never receives, sees or proxies anyone's key.
- **The key never leaves the device.** It is stored in the Keychain and sent only to Garmin's token endpoint. It must
  not appear in backups (ADR-0018), AI reports or exchange messages (ADR-0017), logs, crash reports or analytics. A
  test in `GarminImport`/`GarminSource` should guard the export paths.
- **Rate limits are unpublished and can change.** The client throttles itself (a small per-sync request budget and
  spacing between calls), backs off on 429/427/5xx with jitter, honours `Retry-After`, and never retries in a loop.
  Fetch only what changed (incremental sync).
- **Don't store the key in third-party services.** Saving it in a cloud environment's secrets so that a hosted agent
  can call the API is arguably "disclosing" it to a third party. Record fixtures on your own machine (see the live
  check above). The key used for the live check was saved only briefly and then removed. If in doubt, rotate it.
- **Public distribution (App Store, TestFlight to others) is out of scope for this tier.** That needs the business
  program (Starter, with a backend) or written permission from Garmin, plus a new ADR.

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
    GarminDecoding   JSON → records (HRV night, sleep, daily summary, VO2max, activity). Tolerant: 204 = no data,
                     a field of another type reads as missing, a record without date/id is skipped and counted,
                     only a wrong overall shape throws.
    GarminMapping    records → DailyMetrics / RunActivity / RecordedStrengthActivity. Pure functions.
    GarminEndpoint   request paths and per-request range limits; GarminSyncPlan: days to fetch and windows.
    FIT (later)      Minimal FIT decoder for activity files (records, laps, sessions).
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
- **Idempotent, incremental sync.** Store the last synced day. Revisit today and yesterday for daily metrics,
  and the last seven days for activities so a workout uploaded late in the week still arrives. Include any gap
  since the prior sync, up to the initial 60-day window.
  Upserting a day twice gives the same result.
- **Key lifecycle.** Store the key's expiry date the user picks; a local notification (`LocalAlerts`) and a Settings
  banner 7 days before. On 401 with a fresh token: the key was revoked, so show "Reconnect Garmin".
- **Deduplicate runs.** Garmin also writes runs to Health. Match by start time (±2 min) and duration; keep the
  Garmin record (it has training effect and the FIT file) and drop the Health copy.
- **Secrets.** The key and its expiry date live in the iOS **Keychain**, which encrypts them with keys protected
  by the Secure Enclave. They are never in logs, the JSON backup (ADR-0018), AI reports or exchange messages.
  - **The person enters the key once.** Keychain items survive app updates and re-signing with the same Apple ID (a
    free account re-signs every 7 days; the access group is tied to the team, not to the install). Today they also
    survive deleting and reinstalling the app, though Apple does not promise this.
  - **The key item is `kSecAttrSynchronizable` with `kSecAttrAccessibleAfterFirstUnlock`.** iCloud Keychain then
    keeps it end-to-end encrypted in the person's own iCloud account and brings it back on a new iPhone or after a
    restore. That is the owner's storage, not a third party (Supplemental Terms §1). Without iCloud Keychain it
    stays on the device. It must not be `ThisDeviceOnly`, because that is lost on a device restore.
  - **The 24 h token is a separate item**, `ThisDeviceOnly` and not synchronised: it is cheap to mint again.
  - **Losing the key is recoverable.** If no key is found, Settings explains how to create one. A key that Garmin
    rejects (401 on the token call) shows "Reconnect Garmin". A banner and a local notification warn 7 days before
    the expiry date the person picked (30 days to 1 year).
- **Kill switch.** Disconnecting deletes the key and token; imported values stay (they are the user's data,
  `sources` shows where they came from).
- **Provenance.** `DailyMetrics.sources` already records Garmin; reasons on Today can say "HRV from Garmin".

### Strength workouts recorded on the watch

Garmin returns strength workouts started on the watch as `strength_training` activities, with heart rate,
`activityTrainingLoad`, training effect and the sets and reps the watch counted. The same workout is usually also
logged in Overreach. Rules, so nothing is counted twice and the two never disagree:

1. **The logged session is the source of truth** for exercises, sets, reps, weights and RPE. The watch's set and rep
   counts are never imported into it (watches miscount sets, and Garmin's exercise categories don't map to the catalog).
2. **Garmin strength activities are never turned into sessions.** They become `RecordedStrengthActivity` values
   (Domain), which hold only what the watch measures.
3. **`StrengthActivityMatching` (Domain, pure, tested) pairs them by time:**
   - the intervals must overlap by at least half of the shorter one, so starting the watch early or stopping it late
     still matches, and another workout later that day does not;
   - a session without an end time matches a recording that starts within 15 minutes;
   - pairing is one to one, best overlap first, and does not depend on input order.
4. **A matched recording enriches its session** (heart rate, Garmin load, training effect) when it is shown or
   analysed. Nothing is written into `StrengthSession`, so no stored data changes (ADR-0018) and a re-sync just
   re-matches.
5. **An unmatched recording** is a workout trained without logging it. It appears chronologically in the History
   list with read-only details and a **Log this workout** button, which opens a new session with the watch's times
   (it then pairs with the recording and is not written to Apple Health again). Until logged it is never counted as
   a session. Strength workouts other apps wrote to Apple Health (e.g. the Apple Watch) are recordings too:
   `CombinedRecordedStrengthSource` merges both sources and `StrengthActivityMatching.removingDuplicates` keeps one
   record per workout, Garmin first. The AI context adds a matched recording as `sessions[].watch`. Its Garmin load
   is kept apart from
   sRPE load: the two are different units and must not be added together in ACWR without an evidence-based
   conversion (step 5).
6. **Runs follow the same rule against Apple Health:** a Garmin run and the copy Garmin Connect writes to Health are
   the same run. Keep the Garmin one, since it has load, training effect and the FIT file. The History list, calendar and
   AI report use `RunDeduplication`. The calendar reads one day on each side of the month so copies around
   midnight can be matched before the run count and distance are assigned to the preferred record's month.

Overreach does not write a session to Apple Health when another app already recorded the same workout there, and
removes its own copy once the watch's workout arrives (ADR-0023).

### Setup and onboarding (as built)

- **First-run setup** asks "Which devices do you use?" (Apple Watch, Garmin, another watch or ring, only the iPhone)
  with animated cards. The answer is stored in `AthleteProfile.wearables` (optional, unknown values dropped:
  ADR-0018). Picking Garmin opens the Garmin setup on Continue; Apple Health can be allowed from the same step.
- **Garmin setup** (`GarminSetupView`): what you get → create the key (Garmin Connect opens in-app at the key page,
  1 year recommended) → paste (system `PasteButton`, no clipboard prompt). Checking, saving in the Keychain and the
  first 60-day import follow on their own. One sheet at the app root serves the first-run setup, Today and Settings.
- **Later:** Settings → Garmin (status, last sync, key expiry with a warning and badge, sync now, renew, disconnect),
  and a "Connect your Garmin" card on Today for someone who said they use one, or when nothing is connected.
- **Today shows only what sources measure:** a tile appears when a value exists today or in the last 7 days. An
  iPhone alone shows steps; an Apple Watch adds sleep, HRV and resting HR; Garmin adds Body Battery and stress.

## 7. Plan

| Step | Content | Where |
|---|---|---|
| 0 | Done (2026-11-20): checked against Garmin's official OpenAPI document, FAQ, client and Supplemental Terms, and live with a real key; synthetic fixtures recorded; ADR-0022 accepted. Rate limits remain unpublished by design. | docs |
| 1 | Done (2026-11-20): `GarminImport` decodes HRV, sleep, daily summaries v2, VO2max and activities, maps them to `DailyMetrics`, `RunActivity` and `RecordedStrengthActivity`, and plans the requests (first sync of 60 days = 6 requests). Tested against the fixtures. | OverreachCore |
| 2 | Done (#65): `GarminService` (GarminImport) implements `GarminAccount` and `MetricsSource`: token minting and reuse, spacing and backoff, incremental sync, activity paging, cache. `GarminSource` supplies the Keychain, URLSession and the cache file. Wired in `AppContainer`. | Core, Kit, App |
| 3 | Done (#65, #66): `GarminSetupModel` + `GarminSetupView` (three steps), Settings → Garmin, the devices step of the first-run setup, the Today card, an expiry notification a week before, translations. | SettingsPresentation, Feature* |
| 4 | Done: Garmin HRV feeds `ReadinessRules`; every HRV value carries its statistic (`HRVMetric`) and baselines only compare nights of one kind (ADR-0024, `hrv-metrics`). | Domain, Analytics, `docs/evidence.md` |
| 5 | Partly done: Garmin runs are deduplicated against Health copies in the AI report and the History calendar, which shows their training load and training effect when available. Strength is paired by `StrengthActivityMatching` and Health writes are deduplicated (ADR-0023). History shows watch metrics on matched strength sessions and lists watch-only workouts. Next: walks (`ActivitySource`) and our own acute/chronic load from per-activity load (evidence first). | Core + Kit |
| 6 | FIT decoding (laps, HR, power) for run load and the AI report. | OverreachCore |
| 7 | Women's health → `CycleSource` (ADR-0009). | Core + Kit |

Steps 1–4 are the shippable unit for phase 2 (v0.2). `ReleaseNotes.all` gets an entry when step 3 lands.

### Decided questions

- **HRV statistic.** Garmin reports nightly RMSSD and Apple Health stores SDNN. `DailyMetrics.hrvMetric` labels every
  value, merging keeps a value with its label, and readiness and Today only compare nights of one kind
  ([ADR-0024](../adr/0024-hrv-baselines-per-statistic.md)). See the [HRV research note](hrv-sources.md) for the
  evidence and the [follow-up proposal](../adr/0025-hrv-one-series-per-metric.md) for retaining both readings.
- **Body Battery and stress** are shown on Today when Garmin provides them, as context. They are proprietary scores
  and are never a rule input unless evidence supports it (`composite-scores`).
- **Daily summary v2** carries resting HR, steps, stress, Body Battery, respiration and SpO2 in one call; the separate
  endpoints are not used.

### Known limitations and corner cases

- **First sync during Today's load.** `GarminService` syncs when metrics are read and the last sync is older than
  30 minutes, so a launch after a long time can wait for a few requests before Today shows data. Errors are
  swallowed there and shown in Settings.
- **"Range too long" is not split again.** Requests follow the documented limits; if Garmin lowers one, a 400 stops
  that sync (reported as "Garmin isn't answering") until the limit in `GarminEndpoint` is updated.
- **Rate limits are unpublished.** The client spaces requests and retries at most twice, then stops the sync.
- **Disconnecting keeps imported data.** The cache stays and still feeds Today; deleting it is a future option.
- **Cached nights from before `hrvMetric` existed** have no label and form their own group until they age out (the
  integration had not shipped to users then).
- **Key lifetime is what the person says.** Garmin does not report it; the reminder and the Settings warning use
  the lifetime picked in the setup (1 year preselected), counted from when the key was pasted.
- **Notification permission** is asked when the expiry reminder is first scheduled; if refused, the Settings warning
  and badge remain.
- **Health workout deduplication is one way.** If the person deletes the watch's workout from Apple Health, the app
  does not write its own back until the session is edited (ADR-0023).
- **iCloud Keychain off or another Apple ID.** The key then stays on this iPhone only: a new phone needs the key
  pasted again (or a new key).
- **Strength recordings without a logged session** appear in the History list. The calendar's session count still
  reflects workouts logged in Overreach.
- **Not verified on a device yet:** the setup flow, the Keychain item and the Health deduplication have only been
  built and unit tested.

### Remaining open questions

- Exact rate limits; a first sync of 60 days is about 6 requests plus activity pages.
- How to combine Garmin's per-activity load with sRPE load in ACWR (different units): needs evidence before a rule.

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
- Garmin Connect Personal API Supplemental Terms (last updated 2026-10-01), shown when creating a key.
