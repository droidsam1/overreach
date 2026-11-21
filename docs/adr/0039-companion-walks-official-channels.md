# 0039 — Dog walks from a pet tracker through official channels only

- **Status:** Proposed
- **Date:** 2026-11-21

## Context

The athlete walks a dog with a Tractive collar several times a day. ADR-0010 lets the profile declare those walks as
fixed, but the walk data cannot tell them apart. Research on 2026-11-21 (`docs/design/companion-walks.md`) found:

- Tractive has no official public API. Community clients log in to `graph.tractive.com` with the account password and
  a client id copied from Tractive's web app. The main client dropped position history in October 2026. Tractive's
  terms could not be checked.
- A Tractive Walk is recorded with the phone's GPS, so it describes the athlete's own walk, which the watch or Health
  usually records too. The collar reports a position only every 2–60 minutes outside Live mode.
- Tractive syncs Walks to Strava officially. Strava writes activities to Apple Health. Strava has a documented
  public API, but since 2026 it needs a paid subscription to create an app and restricts AI use of its data.
- Tractive Premium exports location history as GPX or KML.

## Decision

1. A pet tracker adds a **tag** to walks Overreach already has (`WalkBout.companion`). It does not add walks. A single
   pure matcher in Domain (`CompanionWalkMatching`) turns time windows from any source into tags.
2. Sources, in order of preference: Apple Health workouts written by a user-selected companion app (the Tractive →
   Strava → Health chain), then a Tractive GPX/KML export imported by file, then a manual tag. Every source is optional
   and isolated.
3. We do not use Tractive's or any other pet tracker's unofficial API, not even as a fallback (as ADR-0022 for Garmin).
4. A Strava API source is considered only if the Health chain fails on a real device, and needs its own ADR. If it is
   built, each user brings their own Strava app, and Strava-derived data stays out of AI exchange and reports.
5. Coordinates and routes are never stored. Only windows (start, end, distance, confidence) and the tag are kept.
6. The tag explains walks and protects fixed walks. It does not change walking load or the baseline.

## Consequences

- No new credentials or network code for the first two routes. The feature works offline and survives vendor API
  changes.
- Walks recorded in Tractive before Strava was connected only arrive through the GPX/KML export, which needs Tractive
  Premium.
- If Strava stops writing third-party activities to Health, route 1 stops silently. Settings shows the last tagged walk
  per source so the user notices.
- Other trackers (Fi, PitPat) fit the same windows → matcher design if they gain an official export or write to
  Health.
