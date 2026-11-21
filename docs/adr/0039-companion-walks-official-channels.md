# 0039 — Dog walks: confirm in one tap, backfill from the tracker's export

- **Status:** Proposed
- **Date:** 2026-11-21

## Context

The athlete walks a dog with a Tractive collar (Premium plan) several times a day. ADR-0010 lets the profile declare
those walks as fixed, but the walk data cannot tell them apart. Research on 2026-11-21
(`docs/design/companion-walks.md`) found:

- Tractive has no official public API. Community clients log in to `graph.tractive.com` with the account password and
  a client id copied from Tractive's web app. The main client dropped position history in October 2026. Tractive's
  terms could not be checked.
- A Tractive Walk is recorded with the phone's GPS, so it describes the athlete's own walk, which the watch or Health
  usually records too. The collar reports a position only every 2–60 minutes outside Live mode.
- The official ways out of Tractive are a Strava sync and the Premium GPX/KML location export. The athlete does not use
  Strava and will not install it for this.

## Decision

1. A dog walk is a **tag** on a walk Overreach already has (`WalkBout.companion`), never a new walk.
2. The main source is the athlete. The app asks "With <dog>?" on walks at the athlete's usual dog-walk times, learned
   from earlier answers, and one tap confirms. History allows changing any answer.
3. An optional import of the Tractive GPX/KML export tags past walks automatically. The athlete downloads the file
   from my.tractive.com, guided by a three-step sheet with an animated walkthrough. The site opens in
   `SFSafariViewController`, so the app never handles the Tractive login. The file can also arrive as a shared
   document. A single pure matcher in Domain
   (`CompanionWalkMatching`) turns its movement windows into tags. A manual answer always wins.
4. We do not use Tractive's or any other pet tracker's unofficial API, not even as a fallback (as ADR-0022 for Garmin).
   Strava routes are not planned.
5. Coordinates and routes are never stored. Only windows (start, end, distance, confidence), answers and the tag are
   kept.
6. The tag explains walks and protects fixed walks. It does not change walking load or the baseline.

## Consequences

- No credentials and no network code. The feature works offline and cannot break when a vendor changes an API.
- The athlete answers a question on some walks. Learning the usual times keeps that to the walks that are likely dog
  walks.
- The backfill needs Tractive Premium and a manual download from my.tractive.com, up to 60 days per file.
- Other trackers fit the same windows → matcher design if they offer an official export.
