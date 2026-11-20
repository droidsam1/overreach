# Daily activity and walks

Status: design, phases 0–3. Decision and evidence: ADR-0010.

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
2. Otherwise, from Health's step-count samples: a bout is ≥ 10 consecutive minutes with ≥ 60 steps/min,
   merging gaps ≤ 3 min. HR during the bout is attached when available.
3. Steps inside run workouts are excluded from walking.

## Baselines and load (phase 2, `Analytics`)

- Baseline: 28-day median of steps and walking minutes (and walks per day).
- `walkingLoad(day)` = load of walking *above* baseline only. With HR: TRIMP of the bouts minus baseline
  share. Without HR: minutes above baseline × a low intensity factor, × 1.3 if elevation gain is high.
- That load goes into the weekly load comparison (with a configurable weight, default low) and into the
  lower-limb fatigue model (quads, calves, glutes), so a 2-hour hilly walk the day before squats is visible.
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
