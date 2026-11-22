# Walks with the dog from a pet tracker

Status: research done 2026-11-21, decision in [ADR-0039](../adr/0039-companion-walks-official-channels.md) (Proposed),
revised 2026-11-22: the GPX/KML backfill was dropped. First tracker studied: Tractive.

## Question

The athlete walks a dog several times a day. ADR-0010 lets the profile declare those walks as fixed, but the data
cannot tell a dog walk from any other walk. Can Overreach tell which of the walks that Garmin and Apple Health already give were with the dog?

Value for the athlete: Today can say "2 of your usual 3 dog walks" and never suggest dropping a fixed walk. The walking
picture explains spikes ("a long dog walk on Saturday"). Load does not change: habitual dog walks are already in the
walking baseline (`walking-load-baseline`).

## Findings

Checked 2026-11-21. Tractive's own sites (tractive.com, help.tractive.com, graph.tractive.com) are not reachable from
the research environment, so their help pages are cited through search-engine extracts. Sources marked *code* were read
directly.

| # | Finding | Confidence | Source |
| --- | --- | --- | --- |
| F1 | Tractive publishes no public developer API, SDK or partner program. | High: no vendor page, and every client says it is unofficial | [aiotractive README](https://github.com/zhulik/aiotractive), [API Evangelist](https://providers.apievangelist.com/providers/tractive/), [unofficial REST wrapper](https://github.com/dominique-boerner/unofficial-tractive-rest-api) |
| F2 | The community API is `https://graph.tractive.com/4/`. It logs in with `POST auth/token {platform_email, platform_token: <password>, grant_type: "tractive"}` and a fixed client id taken from the web app. The bearer token carries `expires_at`. There is a push channel at `channel.tractive.com/3/channel` and health data at `aps-api.tractive.com/api/1/pet/{id}/health/overview` (daily active, rest and sleep minutes). | High (*code*) | aiotractive 2.1.0 `api.py`, `channel.py`, `trackable_object.py` |
| F3 | Position history is `GET tracker/{id}/positions?time_from&time_to&format=json_segments` (added 2021, documented 2024). aiotractive **removed** it on 2026-10-25 as unused by Home Assistant. It still works as of that date, but nothing tests it any more. | Medium (*code*, git history) | aiotractive commits #22, #218 |
| F4 | The community client retries 429 up to 3 times with 8–60 s jittered backoff and spaces calls 2 s apart. This suggests rate limiting exists but is unpublished. Tractive runs AWS WAF and honeypots against bots. | Medium | aiotractive `api.py`, `tractive.py`; [Tractive engineering blog](https://tractive.com/blog/en/life-at-tractive/tractive-honeypots) |
| F5 | Tractive's general terms could not be read. Whether automated access is allowed is unknown. | — | — |
| F6 | **Walk** is started by hand in the Tractive app (Map → Walk). It uses the **phone's GPS**, not the collar's. A walk lasts 1 min – 6 h, counts elapsed time including breaks, stores distance, duration, route, date and time, and is kept 12 months. Dogs only. | High (vendor help) | [Walk: How-To Guide](https://help.tractive.com/hc/en-us/articles/14932449187858-Walk-How-To-Guide), [LIVE vs WALK](https://help.tractive.com/hc/en-us/articles/19942936227730-What-is-the-difference-between-LIVE-and-WALK-on-the-map-screen) |
| F7 | Outside Live mode the collar reports a position every 2–60 min depending on movement (about every 10 min on the move), and every 30–60 min in Low Power mode. Live mode reports every 2–3 s and switches off after 5 min by default. | High (vendor help) | [How often does the tracker detect a new position?](https://help.tractive.com/hc/en-us/articles/205663461-How-often-does-the-Tractive-GPS-tracker-detect-a-new-position), [Default vs LIVE](https://help.tractive.com/hc/en-us/articles/115003097645-What-is-the-difference-between-Default-and-LIVE-Tracking) |
| F8 | **Tractive → Strava** is an official integration. Walks recorded after connecting sync automatically. Older walks are not backfilled. Strava has no dog-walk activity type. | High (vendor help) | [Connect to Strava](https://help.tractive.com/hc/en-us/articles/18321228901010-Connect-to-Strava-How-To-Guide), [press release](https://tractive.com/blog/en/press/tractive-unveils-integration-with-fitness-app-strava), [Strava idea](https://communityhub.strava.com/t5/ideas/add-dog-walking-as-an-activity-type/idi-p/8086) |
| F9 | **Strava → Apple Health** writes activity type, distance, time and calories. Routes of third-party activities are not written. Whether a Tractive-originated activity is written at all is not documented. | Medium | [Strava: Health App and Strava](https://support.strava.com/hc/en-us/articles/216917527-Health-App-and-Strava), [DC Rainmaker 2022](https://dcrainmaker.com/2022/03/strava-reverses-functionality.html) |
| F10 | **Tractive location export**: Premium only, at my.tractive.com, as `.gpx` or `.kml`, up to 60 days per export, from 365 days of history (Basic plans keep 24 h). | High (vendor help) | [How to export your location history](https://help.tractive.com/hc/en-us/articles/16114120543378-How-to-export-your-location-history), [Premium features](https://help.tractive.com/hc/en-us/articles/360000222729-What-are-the-benefits-of-a-PREMIUM-subscription-plan-) |
| F11 | **Strava API**: OAuth 2 and documented. Reading uses `GET /athlete/activities?after&before&page&per_page`. Default limits are 200 per 15 min and 2,000 per day, with reads at 100 and 1,000. Usage comes back in `X-RateLimit-*` headers, and going over returns 429. New apps run in single-player mode (owner only), and owners can raise that to 10 athletes themselves. Since June 2026 creating an app needs a paid Strava subscription. Webhooks need a public endpoint. | Medium: third-party guides, to confirm on developers.strava.com | [Sahha](https://sahha.ai/blog/strava-api-changes-2026/), [appsforstrava](https://appsforstrava.com/blog/strava-developer-program-changes-2026), [OpenWearables](https://openwearables.io/blog/strava-api-developer-guide-activities-heart-rate-gps-data) |
| F12 | The Strava API Agreement (Nov 2024) bars using API data "directly or indirectly" for AI and ML. The June 2026 update tells developers using it with AI models to ask Strava in writing. Whether one-off inference is allowed has no public answer. The agreement also bars showing one athlete's data to others. | Medium (secondary reporting) | [DC Rainmaker](https://dcrainmaker.com/2024/11/stravas-changes-to-kill-off-apps.html), [TechRepublic](https://techrepublic.com/article/news-strava-api-scraping-crackdown), [Strava community thread](https://communityhub.strava.com/developers-api-7/ai-inference-with-strava-data-is-it-prohibited-under-the-new-api-agreement-13256) |
| F13 | Other trackers are no better. Fi (TryFi) has only an unofficial GraphQL API with password login, which exposes current position and daily summaries, not walks. PitPat's community integration reverse-engineers the app, and its tokens expire every 7 days. No official API was found for PetPace, Invoxia or Halo. | Medium | [pytryfi](https://github.com/sbabcock23/pytryfi), [PitPat HA thread](https://community.home-assistant.io/t/pitpat-dog-gps-tracker/799000) |

What Overreach already has: `WalkBout`s from Garmin walking activities, from Apple Health walking workouts and from
minute steps in Health (`StepWalkDetection`). Cross-source dedupe keeps Garmin first. `RunDeduplication` and
`StrengthActivityMatching` match by "overlap ≥ 50 % of the shorter interval". Garmin's Personal API gives daily steps
(at most 28 days per call) and walking activities with steps. Minute-level steps come from Health
(`docs/design/garmin-integration.md`).

### What the findings mean

- **A Tractive Walk is the human's walk.** It is recorded with the phone the athlete carries. Its route and duration
  describe the athlete's walk, which the watch usually records too. So the useful datum is not a new walk but a **tag**
  on a walk Overreach already has: "this one was with the dog".
- **The collar alone is too sparse for walk boundaries.** At one point every 2–60 min (F7), a 30-min walk has 3–15
  points. Collar history can confirm that the dog was moving during a human walk, not time it precisely.
- **There is no public Tractive API.** The only official ways out of Tractive are the Strava sync (F8) and the Premium
  location export (F10).
- **The athlete does not use Strava** and will not install it for this (decided 2026-11-21). That rules out every
  Strava route, so the best public API in the chain cannot be used.
- **The location export is not worth it** (decided 2026-11-22). It needs a manual download from my.tractive.com every
  few weeks and gives a backfill the one-tap question already covers.

## Options

| Option | Official | Credentials | Fragility | Effort for the athlete | Verdict |
| --- | --- | --- | --- | --- | --- |
| 1. Suggest "With Nanoq?" on walks at the usual times, confirmed in one tap | — (no Tractive data) | None | None | One tap per walk, less once learned | **Main path** |
| 2. Tractive GPX/KML export, imported by file | Yes | None | Very low | Download and import a file every few weeks | Not planned: little value for the effort (2026-11-22) |
| 3. Apple Health fed by Tractive → Strava → Health | Yes | None | Low | Needs a Strava account | Not planned: no Strava |
| 4. Strava API | Yes | User's own paid Strava app | Medium | Needs a paid Strava subscription | Not planned: no Strava |
| 5. Tractive community API | No | Tractive password | High; unknown terms | None | **Rejected**, same reasons as ADR-0022 |

Option 5 is rejected because it would mean:

- storing the Tractive **password** (there is no token-only flow);
- copying a client id from Tractive's web app;
- depending on an endpoint that its main client no longer exercises (F3);
- calling WAF-protected services whose terms we could not read (F4, F5).

ADR-0022 rejected Garmin's unofficial API for the same reasons after it broke every one to two months.

Another idea, inferring the dog from the collar being near the phone (Bluetooth or Wi-Fi), is not viable on iOS. An app
cannot list nearby Wi-Fi devices, and a collar that reports over GPS and cellular does not join the home network. It
could scan Bluetooth only for a peripheral that advertises a known service, and iOS limits scanning in the background.
Being near the phone also does not mean the dog was on the walk. Not verified against the collar itself.

Option 1 needs no Tractive data, because the walk is already known (Garmin, Health or step detection). Only "with the
dog or not" is missing, and the athlete knows it at a glance. Dog walks happen at regular times, so the app can learn
when to ask and stay quiet otherwise.

## Design

```
Garmin walks · Health walks · step-detected walks ──▶ EverydayMovement dedupe ──▶ kept walks
                                                                                   │
        DogWalkSuggestion (usual times) ──▶ "With Nanoq?" Yes/No ──▶ answer ───────┤
                                                                                   ▼
                                                                 WalkBout.companion = .dog
```

Every walk keeps at most one answer. Confirmed walks teach the suggestion its usual times.

### Matching

`CompanionWalkMatching` (Domain, pure, [#155](https://github.com/droidsam1/overreach/issues/155)) applies the answers:

1. An answer covers every copy of the same walk. Two walks from different sources are the same walk when they overlap
   by ≥ 50 % of the shorter interval (as `RunDeduplication`).
2. The tag and the answer survive dedupe. When `EverydayMovement` drops the Health copy of a Garmin walk, the kept walk
   inherits them.
3. It is idempotent and independent of input order. Answers are keyed by the walk's source and start, so re-syncs change
   nothing. On conflicting answers for one walk, "yes" wins.

### Suggest and confirm

`DogWalkSuggestion` (Analytics, pure, [#163](https://github.com/droidsam1/overreach/issues/163)) decides whether to
ask about a walk of 10 min or more that has no answer:

- **Cold start.** With fewer than 10 answered walks, it asks on every such walk.
- **Learned.** It asks only within ±45 min of a usual slot: a time of day with ≥ 3 confirmed dog walks in the last 28
  days. Weekend slots are learned separately once there are enough answers.
- **"No" teaches too.** A slot whose last 5 answers were all "No" stops asking. Any walk can still be tagged from
  History.

Today's movement card and the walk row in History show the question with Yes and No. One tap stores the answer, and
History lets the athlete change it. The question never blocks anything, and an unanswered walk counts as an ordinary
walk. `WalkingRoutine` gains an optional `dogName` for the wording.

### Use in recommendations

[#159](https://github.com/droidsam1/overreach/issues/159):

- Movement details count dog walks against `usualWalksPerDay`.
- Recommendations never suggest dropping a fixed walk, and notes name the dog walks they refer to.
- Load, baseline and spikes are unchanged.

## Reliability and engineering practices

These apply to every part and are acceptance criteria in the issues.

- **No new credentials, no network.** Both paths use data already on the phone or a file the athlete chose. The
  feature cannot break because a vendor changed an API.
- **Official channels only.** No password storage and no impersonation of a vendor's client (ADR-0022).
- **Optional.** With no dog in the profile, or the question turned off, the app behaves exactly as today.
- **Pure core, thin adapters.** Suggestion and matching live in OverreachCore and are
  tested on Linux with synthetic fixtures. Views only render (ADR-0014).
- **Idempotent.** Stable keys for answers. Re-syncing never asks again or doubles a tag.
- **Time.** Matching uses absolute `Date`s. Time-of-day slots use the user's calendar in one place, with tests for DST
  and midnight.
- **Privacy.** Routes and coordinates are never stored, which also protects the home location. The tag and answers
  travel in backups as optional fields (ADR-0018). The dog's name stays out of AI exchange unless the profile is
  already shared.

## Plan and priorities

| Order | Issue | Priority | Depends on |
| --- | --- | --- | --- |
| 1 | [#155](https://github.com/droidsam1/overreach/issues/155) Companion tag, answers and matcher (Domain) | P2 | — |
| 2 | [#163](https://github.com/droidsam1/overreach/issues/163) "With Nanoq?" suggestion and one-tap confirm | P2 | #155 |
| 3 | [#159](https://github.com/droidsam1/overreach/issues/159) Dog walks in Today and movement details | P2 | #155, #163 |

Not planned: the GPX/KML backfill ([#154](https://github.com/droidsam1/overreach/issues/154), #158, #164, #165) and
[#156](https://github.com/droidsam1/overreach/issues/156),
[#157](https://github.com/droidsam1/overreach/issues/157) and [#160](https://github.com/droidsam1/overreach/issues/160)
(the Strava routes).

The feature is P2, not P1. The walking baseline already absorbs dog walks correctly, so the tag improves explanations
and protects fixed walks without changing today's training decision.

## Open questions

- Tractive's general terms (F5). Read them before any revisit of option 5.
