# 0039 — Dog walks: confirm in one tap

- **Status:** Proposed
- **Date:** 2026-11-21, revised 2026-11-22

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
- The first version of this ADR added the GPX/KML export as an optional backfill. On 2026-11-22 the athlete judged it
  not worth a manual download from my.tractive.com every few weeks, since the one-tap question already covers the walks.

## Decision

1. A dog walk is a **tag** on a walk Overreach already has (`WalkBout.companion`), never a new walk.
2. The only source is the athlete. The app asks "With <dog>?" on walks at the athlete's usual dog-walk times, learned
   from earlier answers, and one tap confirms. History allows changing any answer.
3. We do not import Tractive's GPX/KML export. We do not use Tractive's or any other pet tracker's unofficial API, not
   even as a fallback (as ADR-0022 for Garmin). Strava routes are not planned.
4. We do not infer the dog from the collar being near the phone (Bluetooth or Wi-Fi). iOS does not let an app list
   nearby Wi-Fi devices, limits background Bluetooth scanning to peripherals with a known service, and nearness does not
   prove the dog was on the walk. This was not checked against the collar itself.
5. Only the answers and the tag are stored. No coordinates or routes.
6. The tag explains walks and protects fixed walks. It does not change walking load or the baseline.

## Consequences

- No credentials and no network code. The feature works offline and cannot break when a vendor changes an API.
- The athlete answers a question on some walks. Learning the usual times keeps that to the walks that are likely dog
  walks.
- Past walks are tagged only by answering them in History.
- Assuming a dog walk at times where the athlete almost always answers yes, and letting them correct it, is an idea to
  evaluate later. It is not decided.
- A tracker with an official export or API could feed the same tag later, through the same answers.
