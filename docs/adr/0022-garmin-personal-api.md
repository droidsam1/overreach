# 0022 — Garmin data through the official Personal API

- **Status:** Accepted (supersedes 0005)
- **Date:** 2026-11-20

## Context

ADR-0005 chose the unofficial Garmin Connect API to get nightly HRV and other Garmin-only metrics, because the
official API was business-only. Since then:

- In 2026 the unofficial API broke roughly every one to two months: the auth flow changed in March, `garth` was
  deprecated, Cloudflare started blocking clients by fingerprint, and logins hit 401, 429 and 427 errors. Clients
  survive only by impersonating Garmin's app and its TLS stack.
- On 2026-10-21 Garmin opened a free, self-service **Personal API key**: read-only REST pull on
  `personal.connectapi.garmin.com`, with the key exchanged for a 24 h bearer token. It serves the same Connect
  service endpoints the Garmin app uses (checked against Garmin's official OpenAPI document and client): nightly HRV with status and
  baseline, sleep with stages and score, daily summaries (resting HR, steps, stress, Body Battery, respiration,
  SpO2), VO2max, activities with per-activity training load and training effect, FIT files, and the menstrual cycle.
  Training readiness, training status, Garmin's aggregate acute/chronic load and recovery time are not included.

The analysis is in `docs/design/garmin-integration.md`.

## Decision

1. `GarminSource` uses the official Personal API. The user creates a key in Garmin Connect and pastes it into
   Settings; it is stored in the Keychain, and requests go straight from the iPhone to Garmin.
2. We do not implement the unofficial API, not even as a fallback. Proprietary Garmin scores (training readiness
   and status, load, recovery time) are not imported. Overreach computes its own explainable readiness from the raw
   signals (ADR-0020).
3. JSON decoding and mapping live in a new pure module, `GarminImport` (OverreachCore, depends on Domain), tested on
   Linux against recorded fixtures. Networking and the Keychain stay in `GarminSource`.
4. Apple Health remains the base source. Garmin values win where both exist, and the app works fully without
   Garmin.
5. The key is personal (Garmin Connect Personal API Supplemental Terms, 2026-10-01): it is used only by its owner,
   in their own copy of the app, and never shared or disclosed. It stays in the Keychain and is sent only to Garmin;
   it is kept out of backups, AI reports, exchange messages and logs.
6. Rate limits are unpublished and may change, so the client throttles itself, backs off on 429/427/5xx and syncs
   incrementally.
7. Strength workouts recorded on the watch never become sessions. They are paired with logged sessions by time
   (`StrengthActivityMatching`) and only add heart rate and load; the logged session stays the source of truth.

Checked against Garmin's official OpenAPI document, FAQ, client and Supplemental Terms, and live with a real key
(2026-11-20).

## Consequences

- Stable, documented, terms-compliant access for self-built and sideloaded copies, with no password handling.
- We lose Garmin's aggregate scores (readiness, status, acute load, recovery time). Readiness does not need them,
  and acute/chronic load can be computed, with reasons, from the per-activity load we do get.
- Keys expire (30 days to 1 year): the app has to remind the user and handle reconnection.
- Garmin's FAQ says the Personal API is "not intended for commercial applications serving multiple end users". That
  fits self-built, non-commercial copies. Public distribution (phase 4) needs the business program (Starter, which
  needs a backend and a new ADR) or written permission from Garmin.
- If Garmin closes the Personal tier, the app falls back to Health and the check-in. A Connect IQ HRV app remains
  the plan B.
