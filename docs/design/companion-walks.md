# Walks with the dog from a pet tracker

Status: research done 2026-11-21, plan in [#154](https://github.com/droidsam1/overreach/issues/154), decision in
[ADR-0039](../adr/0039-companion-walks-official-channels.md) (Proposed). First tracker: Tractive.

## Question

The athlete walks a dog several times a day. ADR-0010 lets the profile declare those walks as fixed, but the data
cannot tell a dog walk from any other walk. Can Overreach read the dog's walks from the Tractive collar and match them
with the walks, steps and movement times that Garmin and Apple Health already give?

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
- **There is no best public Tractive API.** The best public API in the chain is Strava's, which receives Tractive walks
  officially (F8, F11). The cheapest official channel is Apple Health, if Strava's write-back carries the walk (F9,
  unverified).

## Options

| Option | Official | Network code | Credentials | Fragility | Data | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| 1. Apple Health, fed by Tractive → Strava → Health | Yes, every hop | None | None | Low; Strava has toggled Health sync before (F9) | Start, end, distance, type | **First**, if #156 confirms it |
| 2. Tractive GPX/KML export, imported by file | Yes | None | None | Very low | Collar track points, coarse | **Second**: backfill and no-Strava users |
| 3. Strava API | Yes | New `StravaSource` | User's own OAuth app | Medium: paid tier since 2026, terms changed twice in 18 months | Full activity, name, device | **Third**, only if 1 fails; own ADR |
| 4. Tractive community API | No | New client, password | Tractive password | High; unknown terms | Positions, daily health | **Rejected**, same reasons as ADR-0022 |
| 5. Manual tag in History | — | None | None | None | Tag only | Always available, as the fallback |

Option 4 rejected because it would mean storing the Tractive **password** (there is no token-only flow), copying a
client id from Tractive's web app, depending on an endpoint that its main client no longer exercises (F3), and
running against WAF-protected services whose terms we could not read (F4, F5). ADR-0022 rejected Garmin's unofficial
API for the same reasons after it broke every one to two months.

## Design

```
Tractive app ──Walk──▶ Strava ──write──▶ Apple Health ──HKWorkout(walking, source=Strava)──┐
my.tractive.com ──GPX/KML export──▶ Files ──▶ TrackImport (pure) ──movement windows────────┤
(Strava API, optional) ──▶ StravaSource ──▶ StravaImport (pure) ──windows──────────────────┤
                                                                                           ▼
Garmin walks · Health walks · step-detected walks ──▶ EverydayMovement dedupe ──▶ CompanionWalkMatching
                                                                                           │
                                                              WalkBout.companion = .dog ◀───┘
```

All sources produce **companion windows** (start, end, source, confidence). They never produce walks directly. One
matcher turns windows into tags. This keeps a single rule, lets sources be added or removed without touching
analytics, and makes every source optional.

### Matching

`CompanionWalkMatching` (Domain, pure, [#155](https://github.com/droidsam1/overreach/issues/155)):

1. Candidate pair: a walk bout and a window that overlap by ≥ 50 % of the shorter interval (as `RunDeduplication`),
   with start times at most 10 min apart. The phone is often started after leaving home, and clocks differ.
2. Assignment: each window tags at most one bout. The largest overlap wins, and ties go to the earlier start, so the
   result does not depend on input order.
3. Low-confidence windows (sparse collar tracks) need ≥ 70 % overlap.
4. A window with no matching bout becomes a tagged bout only when its source recorded the walk itself (Health or
   Strava, the watch was not worn). Collar-only windows never create walks.
5. The tag survives dedupe: when `EverydayMovement` drops the Health copy of a Garmin walk, the kept walk inherits the
   tag.
6. Idempotent: windows are keyed by source id (HealthKit UUID, Strava activity id), or for file imports by start and
   end rounded to the minute. Re-imports and re-syncs change nothing.

Thresholds are product heuristics, recorded as `walk-companion-matching` in `docs/evidence.md` when #155 lands.

### Route 1: Apple Health through Strava

[#156](https://github.com/droidsam1/overreach/issues/156) (device check) →
[#157](https://github.com/droidsam1/overreach/issues/157). Health walking workouts whose source bundle is a
user-selected companion app become windows. Reads are incremental with `HKAnchoredObjectQuery`, and deletions remove
their window. With no network and no credentials, the failure modes are those of HealthKit, which the app already
handles.

### Route 2: Tractive location export (GPX/KML)

[#158](https://github.com/droidsam1/overreach/issues/158). A pure `TrackImport` module turns track points into
movement windows (speed ≥ 0.5 m/s for ≥ 8 min, joining gaps ≤ 5 min, confidence from point density). It is imported
through Files like the Strong CSV (ADR-0011), with a preview before saving. Coordinates are discarded after windows are
computed.

### Route 3: Strava API

[#160](https://github.com/droidsam1/overreach/issues/160), only if route 1 fails. It follows the Garmin Personal API
model (ADR-0022): each user brings their own single-player Strava app, OAuth runs in `ASWebAuthenticationSession`,
and the refresh token stays in the Keychain. Sync polls on launch and foreground with a high-water mark, a
header-driven rate limiter, bounded retries and a per-session circuit breaker. Strava-derived fields are kept out of
AI exchange and reports (F12).

### Use in recommendations

[#159](https://github.com/droidsam1/overreach/issues/159). Movement details count dog walks against
`usualWalksPerDay`. Fixed walks are never suggested away. Notes name the dog walks they refer to. Load, baseline and
spikes are unchanged.

## Reliability and engineering practices

These apply to every route and are acceptance criteria in the issues.

- **Optional and isolated.** Each source is a separate module behind a protocol. With every source off, the app
  behaves exactly as today. A kill switch for each source sits in Settings.
- **Official channels only.** We accept no password storage and no impersonation of a vendor's client (ADR-0022).
- **Pure core, thin adapters.** Parsing, movement detection and matching live in OverreachCore and are tested on Linux
  with synthetic fixtures. HealthKit, Files and network adapters only move bytes.
- **Idempotent, incremental sync.** Anchors (HealthKit) or high-water marks with a one-day overlap (Strava), and
  stable keys for every window. Re-running any sync is safe.
- **Tolerant decoding.** Unknown fields are ignored and every metric is optional. A malformed record is skipped and
  counted, not fatal. A malformed file is rejected as a whole with a clear message.
- **Bounded network behaviour (route 3).** Timeouts, at most two retries with jittered exponential backoff, honouring
  `Retry-After`, stopping at 80 % of the rate window, and a circuit breaker for the rest of the session. Sync runs only
  on launch and foreground (iOS background refresh is not guaranteed).
- **Observable.** Each source shows its last sync, items read and its last error in Settings. Logs carry counts and
  status codes, never tokens, coordinates or names.
- **Time.** All matching uses absolute `Date`s. Day bucketing happens once, in the user's calendar, outside the
  matcher. Tests cover DST and midnight.
- **Privacy.** Routes and coordinates are never stored, which also protects the home location. Tags travel in backups
  as an optional field (ADR-0018). Credentials never go into backups, reports, AI exchange or logs.
- **Contract drift.** Fixtures are recorded from real responses and anonymised before they are committed. A failing
  decode in production shows as a source status, not a crash.

## Plan and priorities

| Order | Issue | Priority | Who | Depends on |
| --- | --- | --- | --- | --- |
| 1 | [#155](https://github.com/droidsam1/overreach/issues/155) Companion tag and matcher (Domain) | P2 | Agent | — |
| 2 | [#156](https://github.com/droidsam1/overreach/issues/156) Device check Tractive → Strava → Health | P2 | Person with iPhone | — (in parallel) |
| 3 | [#157](https://github.com/droidsam1/overreach/issues/157) Tag walks from companion apps in Health | P2 | Agent | #155, #156 |
| 4 | [#159](https://github.com/droidsam1/overreach/issues/159) Dog walks in Today and movement details | P2 | Agent | #155 + a source |
| 5 | [#158](https://github.com/droidsam1/overreach/issues/158) Tractive GPX/KML import | P3 | Agent | #155 |
| 6 | [#160](https://github.com/droidsam1/overreach/issues/160) Strava API source (conditional, new ADR) | P3 | Agent | #156 negative |

Why P2 and not P1: the walking baseline already absorbs dog walks correctly. The tag improves explanations and
protects fixed walks, but does not change today's training decision.

## Open questions

- #156: does a Tractive walk reach Health through Strava, with which type, source bundle, name and metadata, and with
  elapsed or moving time?
- Tractive's general terms (F5). Read them before any revisit of option 4.
- Strava's current rate limits and API Agreement text, before #160.
- Whether the GPX export includes per-point timestamps in UTC (expected for GPX 1.1, to confirm with a real export,
  which must not be committed).
