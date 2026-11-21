# Daily activity and walks

Recovery phase shipped ([#103](https://github.com/droidsam1/overreach/issues/103)). Decision: ADR-0010.

## Shipped

- `EverydayMovement` (Analytics): 28-day median steps and walking minutes, extra walking minutes above the usual
  day, the `walkingSpike` and `stepsFarBelowBaseline` signals and cross-source walk dedupe (Garmin first).
  Defaults are in `walking-load-baseline` (`docs/evidence.md`).
- Apple Health walking and hiking workouts become `WalkBout`s.
- Garmin walking and hiking activities (`walking`, `casual_walking`, `hiking`, …) become `WalkBout`s with their
  steps, distance, heart rate and elevation. They are kept in the Garmin cache; a cache from before walks fetches
  the activities of the first-sync window once more so the walking baseline has its history.
- `StepWalkDetection` (Domain) finds walks nobody started on the watch in Apple Health's minute-by-minute steps
  (rules below). Minutes inside any recorded workout and minutes above 140 steps/min (running cadence, e.g. a
  Garmin run that is not in Apple Health) are excluded. Detected walks use the fallback load estimate to avoid
  querying weeks of heart-rate samples.
- Today: the steps tile shows the usual day, and an **Everyday movement** card lists the signals and, on a red
  day, an easy walk (or "keep your usual walks easy" with a dog or fixed walks). Steps come from the merged daily
  metrics, so Garmin's count wins over Apple Health's.

- The deload check compares strength and excess walking load with the usual week. On Today, a spike before a
  scheduled run or a lower-body routine adds a warm-up cue. An explicit rest day can suggest an easy walk.

See the recommendations table for later planning and simulation work.

## Principle

Walking is the user's background activity. Habitual walking is part of their baseline and costs nothing;
spikes above it add a small load; walking is also the default recovery tool. The user's routine (a dog,
a commute) is a constraint the engine adapts to, never something it removes.

## Domain (phase 0 – planned)

```swift
public struct WalkBout: Codable, Sendable {
    public var start: Date
    public var durationSeconds: Double
    public var steps: Int?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var elevationGainMeters: Double?
    public var source: DataSourceKind          // health workout, garmin activity, detected from steps
}

public struct DailyActivity: Codable, Sendable {
    public var day: CalendarDay
    public var steps: Int?                     // also kept in DailyMetrics for the readiness view
    public var walks: [WalkBout]
}

public struct WalkingRoutine: Codable, Sendable {   // part of AthleteProfile
    public var hasDog: Bool
    public var usualWalksPerDay: Int?
    public var walksAreFixed: Bool             // can't be skipped, only adjusted
    public var canRunDuringWalks: Bool         // e.g. jog with the dog
    public var flexibleSplit: Bool             // fine to do more/shorter or fewer/longer walks
}

public protocol ActivitySource: Sendable {
    func activity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity]
}
```

## Detecting walks (phase 2)

1. Health workouts with activity type walking/hiking, and Garmin walking activities (deduplicated by time
   overlap; Garmin wins).
2. Otherwise, from Health's step-count samples: a bout is ≥ 10 consecutive minutes with 60–140 steps/min,
   merging gaps ≤ 3 min. Recorded workouts can supply HR.
3. Steps inside run workouts (any recorded workout) and minutes at running cadence are excluded from walking.

## Baselines and load (phase 2, `Analytics`)

- Baseline: 28-day median of steps and walking minutes (and walks per day).
- `EverydayMovement.walkingLoads` applies each day's prior baseline. It assigns excess minutes across bouts
  in proportion to their duration and estimates effort from heart-rate reserve when the profile supplies resting
  and maximum HR. The effort falls back to 1, or 1.3 at 50 m of ascent per kilometre. The estimated effort-minutes
  receive a configurable weight of 0.25.
- The weekly comparison uses duration × logged session RPE, or the mean of all working-set RPEs, for strength.
  An incomplete strength record omits the comparison. The deload rule still requires a performance signal.
- The movement card uses a recent walking spike as possible leg fatigue and suggests a warm-up check before a
  scheduled run or lower-body routine.
- Signals: `stepsFarBelowBaseline(days:)`, `walkingSpike(percentAboveBaseline:)`.

## Recommendations (phase 3)

Each one names its reason and respects `WalkingRoutine`:

| Situation | Suggestion |
| --- | --- |
| Red readiness, or day after heavy legs / long run | Easy walk 20–40 min (active recovery: small effect on soreness and fatigue). |
| Steps far below baseline for ≥ 3 days | Add movement: an extra or longer walk. |
| Heavy leg day or key run within 24 h and legs fatigued | Keep today's walks easy and flat; avoid a big spike. |
| Green day, fresh legs, no hard run within 24–48 h, `canRunDuringWalks` | Optional: 10–20 min easy jog in one of the walks (Z1–2). Counts as a run. |
| Walking spike yesterday + leg session today | Mention it as a reason; may lower leg targets via the fatigue model. |
| `flexibleSplit` and user asks | Offer more/shorter or fewer/longer walks as a lifestyle option, without a recovery claim. |

"What if I run X km today?" (phase 3) also simulates "what if I walk X min / jog with the dog".

## Placement

| Phase | Work |
| --- | --- |
| 0 — Foundation | Domain types above, `ActivitySource` protocol, ADR-0010. |
| 2 — v0.2 | Health/Garmin implement `ActivitySource`; walk detection; baselines; walking load into ACWR and leg fatigue; Today shows steps and walks vs baseline; onboarding asks about the walking routine (dog, walks per day, fixed or not). |
| 3 — Intelligence | Walking recommendations above; simulation; walks in the shareable report. |
