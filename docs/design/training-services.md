# Training services: one source of truth per question

Status: planned (reviewed 2026-11-21). Decision: ADR-0035.

## Continue from here

Take the first task below whose boxes are not all checked. Each task is one pull request and leaves `main`
working. Task 2 replaces task 1 of [deloads and breaks](deloads-and-breaks.md): check its box there when done.
After task 5, update the layout and dependency rules in `AGENTS.md` and `CODING_STANDARDS.md`.

## Inventory of drift

Found on `main` at 569b67f (2026-11-21). Line numbers move; search for the names.

| Question | Where it is answered today | How the answers differ |
| --- | --- | --- |
| Last deload or break | `DeloadAdvice.make` (`profile.deloads.last?.start`), `PlanAnalysis.run` (latest planned deload's end) | Start vs end, `last` vs `max`; see the run reading below. Today showed 51 weeks, Plan 2. |
| Deload week in progress | `DeloadAdvice.make`, `WorkoutModel` (`deloadPlan`), `PlanAnalysis.run` | Three copies of the same date check; the workout's plan comes from `DeloadAdvisor.Settings()` defaults. |
| Runs in a range | `TodayModel.readRecentRuns`, `PlanModel.analyse`, `HistoryRunReadings.load`, `AskAIModel.runs` | Today asks unavailable sources and marks any error as failed; Plan and Assistant skip unavailable ones; Assistant drops errors silently; History keeps three states. Deduplication happens in some callers and again inside `DeloadDetection`. |
| Daily metrics | `TodayModel` (merged per day, source priority), `AskAIModel.metrics` | The Assistant sends one row per source and day, unmerged. |
| Stalled lifts | `WorkoutModel`, `PlanAnalysis.run`, `DeloadAdvisor`, `ContextPackBuilder` | Different settings fallbacks (skip the lift, or a 2.5 kg default) and different lift sets (all, main, any). |
| Progression settings for an exercise | 13 call sites build `settings[id] ?? ProgressionSettings(for:)` or `ProgressionSettings(incrementKg: 2.5)` | Same as above; routine prescriptions are applied in `DeloadDetection` only. |
| Recovery signals ("HRV low") | `ReadinessRules` (readings), `RecoveryTrend` (days of 7-day trend) | Same words for two measures. |
| History windows | `DeloadDetection.historyDays` read by `TodayModel` and `PlanModel`; Assistant and History choose their own | Each screen decides how much history a rule needs. |

The rules themselves (`DeloadDetection`, `DeloadAdvisor`, `StallDetection`, `ReadinessRules`) exist once. The
drift is in what feeds them and how they are combined, which is the job of an application layer.

## Target shape

```
Presentation (Today, Plan, Workout, History, Assistant)   AIExchange
                 \                                       /
                  TrainingServices   (reads sources, composes rules, answers questions)
                  /                \
            Analytics (pure rules)   Domain (entities, source and repository protocols)
```

`TrainingServices` exposes one entry point per question, for example:

```swift
public struct TrainingServices: Sendable {
    public init(sessions: any WorkoutRepository, profiles: any ProfileRepository, exercises: any ExerciseRepository,
                progression: any ProgressionSettingsRepository, routines: any RoutineRepository,
                metrics: [any MetricsSource], recordedStrength: (any RecordedStrengthSource)?,
                activity: [any ActivitySource], calendar: Calendar)

    public func runs(in range: ClosedRange<Date>) async -> SourceReading<[RunActivity]>
    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async -> SourceReading<[DailyMetrics]>
    public func recoveryStatus(on day: CalendarDay) async -> RecoveryStatus
    public func liftStatus(on day: CalendarDay) async -> [LiftStatus]
    public func deloadRecommendation(on day: CalendarDay) async -> DeloadRecommendation?
}
```

Names and signatures are a starting point. `SourceReading` carries the values, the sources read and those that
failed, so screens can show provenance (ADR-0032). `App/Sources/AppContainer.swift` builds one instance and passes
it to every model that needs it.

## Implementation backlog

### 1. Module and shared reading

- [ ] Add the `TrainingServices` target and library to `Packages/OverreachCore/Package.swift` (depends on `Domain`,
  `Analytics`) and a test target.
- [ ] Move run reading into it: skip unavailable sources, record an available source that throws as failed, remove
  duplicates with `RunDeduplication`. Same for daily metrics (merged per day in source order, as `TodayModel` does)
  and watch strength recordings.
- [ ] Switch `TodayModel`, `PlanModel`, `HistoryRunReadings` and `AskAIModel` to it. The Assistant now sends one
  merged row per day.
- [ ] Tests with fake sources: unavailable, failing, duplicated runs, two sources for one day.

Finish line: `grep -rn "\.runs(from\|dailyMetrics(in" Packages/OverreachCore/Sources/Presentation` finds nothing.

### 2. Recovery status

- [ ] `RecoveryStatus`: the last recovery (day, kind, and discipline once deloads task 3 lands), the deload week in
  progress with its plan, and the breaks waiting for an answer.
- [ ] Use it in `DeloadAdvice`, `PlanModel`/`PlanAnalysis` and `WorkoutModel`; `DeloadAdvisor.proposal` takes the
  last recovery instead of `lastDeload` plus `detectedDeloads`.
- [ ] Without any recovery, the interval signal says how much history there is, not weeks since the first session.
- [ ] Tests: one fixture gives the same last recovery to Today, Plan and Workout; an accepted deload two weeks ago
  gives no interval signal.

Finish line: [deloads task 1](deloads-and-breaks.md#1-one-last-recovery-for-today-and-plan) is checked.

### 3. Lift status and progression settings

- [ ] One function resolves the progression settings of an exercise (stored, else the exercise default, plus the
  routine prescription when a routine applies). Replace the 13 call sites.
- [ ] `LiftStatus` per exercise: settings in use, trained recently or not, stall status with its explanation. Use it
  in `WorkoutModel`, `PlanAnalysis`, `DeloadAdvice` and `ContextPackBuilder`.
- [ ] Tests: the same lift is stalled or not on every screen and in the AI context.

Finish line: `StallDetection.status` and `ProgressionSettings(for:)` are called only from `TrainingServices` and
`Analytics`.

### 4. Readiness and the deload recommendation

- [ ] Move the readiness and deload composition out of `TodayModel`/`DeloadAdvice` (which inputs, which windows)
  into `TrainingServices`; `DeloadAdvice` keeps only the texts.
- [ ] Give the AI context pack the same readiness and deload answers Today shows.
- [ ] Distinct names for the per-reading and 7-day-trend HRV counts in the returned types.

Finish line: the AI context and Today state the same readiness level and deload proposal for the same day.

### 5. Guard the boundary

- [ ] Add a check (SwiftLint `custom_rules` or `scripts/check-repo.py`) that fails when a file under
  `Packages/OverreachCore/Sources/Presentation` calls `.runs(from`, `.dailyMetrics(in`, `DeloadDetection.`,
  `DeloadAdvisor.`, `StallDetection.status` or `ReadinessRules.readiness`.
- [ ] Mark ADR-0035 accepted and add `TrainingServices` to the layout and dependency rules in `AGENTS.md`.

Finish line: the check passes on `main` and fails on a test file that breaks the rule.
