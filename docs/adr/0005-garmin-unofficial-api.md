# 0005 — Garmin Connect via unofficial API, optional and isolated

- **Status:** Accepted (to be superseded by 0022, proposed)
- **Date:** 2026-11-16

## Context

Garmin Connect writes heart rate, sleep, steps and activities to Apple Health, but not HRV, Body Battery,
training status, training readiness or load. The official Garmin Health API is only for approved businesses.

## Decision

- Read Garmin-only metrics with the unofficial Garmin Connect API, implemented in the `GarminSource` module.
- The user signs in once; OAuth tokens are stored in the iOS Keychain. Requests go directly from the iPhone
  to Garmin — no intermediate server, credentials never leave the device.
- `GarminSource` implements the same `MetricsSource` protocol as Apple Health. The app works fully without it.
- Import every metric the watch provides; all fields are optional because models differ (e.g. Forerunner
  265 vs 255).

## Consequences

- Garmin can change or block the API at any time; when it breaks, the app degrades to Health + check-in.
- Possible terms-of-use concerns: the module is optional, clearly labelled, and the project states it is not
  affiliated with Garmin.
- Plan B: a Connect IQ watch app that measures HRV directly (future ADR).
