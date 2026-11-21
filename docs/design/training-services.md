# Training services: one source of truth per question

Status: tasks 1–5 implemented (reviewed 2026-11-21). Decision: ADR-0035.

## Continue from here

Continue with [breaks per discipline](deloads-and-breaks.md#3-breaks-per-discipline-counted-automatically).

## Inventory of drift

Found on `main` at 569b67f (2026-11-21). Line numbers move; search for the names.

| Question | Where it is answered today | How the answers differ |
| --- | --- | --- |
| Last deload or break | `DeloadAdvice.make` (`profile.deloads.last?.start`), `PlanAnalysis.run` (latest planned deload's end) | Start vs end, `last` vs `max`; see the run reading below. Today showed 51 weeks, Plan 2. |
| Deload week in progress | `DeloadAdvice.make`, `WorkoutModel` (`deloadPlan`), `PlanAnalysis.run` | Three copies of the same date check; the workout's plan comes from `DeloadAdvisor.Settings()` defaults. |
| Runs in a range | `TodayModel.readRecentRuns`, `PlanModel.analyse`, `HistoryRunReadings.load`, `AskAIModel.runs` | Today asks unavailable sources and marks any error as failed; Plan and Assistant skip unavailable ones; Assistant drops errors silently; History keeps three states. Deduplication happens in some callers and again inside `DeloadDetection`. |
| Daily metrics | `TodayModel` (merged per day, source priority), `AskAIModel.metrics` | The Assistant sends one row per source and day, unmerged, as `docs/ai-exchange.md` documents; both now read through `SourceReader`. |
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

- [x] Add the `TrainingServices` target and library to `Packages/OverreachCore/Package.swift` (depends on `Domain`,
  `Analytics`) and a test target.
- [x] Move run reading into it (`SourceReader`): skip unavailable sources, record an available source that throws as
  failed, remove duplicates with `RunDeduplication`. Same for daily metrics (merged per day in source order, as
  `TodayModel` did). Watch strength recordings and walks (`ActivitySource`) are read in one call each and move with
  the services that use them (tasks 2–4).
- [x] Switch `TodayModel`, `PlanModel`, `HistoryRunReadings` and `AskAIModel` to it. Task 4 preserves the
  Assistant's rows per source.
- [x] Tests with fake sources: unavailable, failing, duplicated runs, two sources for one day.

Finish line: presentation reads runs through `SourceReader` and daily metrics through `TrainingRecordLoader`.

### 2. Recovery status

Shipped as pure rules in `Analytics` (`RecoveryHistory`), since they need no reading of their own; the inputs to
`DeloadDetection` move into `TrainingServices` with task 4.

- [x] `RecoveryHistory.lastRecovery` (last day and kind; discipline once deloads task 3 lands) and
  `RecoveryHistory.deloadInProgress`.
- [x] Use them in `DeloadAdvice`, `PlanAnalysis` and `WorkoutModel`; `DeloadAdvisor.proposal` takes the last
  recovery instead of `lastDeload` plus `detectedDeloads`. The week without repeat advice follows any recovery.
- [x] Without any recovery, the interval signal says how much history there is (`noDeloadInHistory`).
- [x] Tests: `RecoveryHistoryTests`; in `DeloadAdviceTests`, Today and `PlanAnalysis` count from the same deload,
  and an accepted deload gives no interval signal.

### 3. Lift status and progression settings

Shipped as pure rules in `Analytics`, as in task 2.

- [x] `ProgressionTargets.settings(for:stored:focus:prescription:)` is the one resolver: stored settings, else the
  exercise default (2.5 kg increment when the exercise left the catalog), the focus's scheme, and a routine's
  prescription on top. `DeloadDetection`, `SessionReview`, `PlanAnalysis`, the deload advice and preview, and the
  plan importer use it. `ProgressionSettings(for:)` stays only where a screen compares with the defaults before
  saving.
- [x] `LiftStatus` per exercise: settings in use (from the latest session that trained it: its routine's
  prescription and focus), progression history and stall status. `ExposureIndex.progressionExposures` leaves out
  unfinished exercises, as the logger does; Plan used to count them. `WorkoutModel`, `PlanAnalysis`,
  `DeloadAdvice` and `ContextPackBuilder` use it. "Trained recently" comes with deloads task 2.
- [x] Tests: `LiftStatusTests` (unfinished exercises, routine prescription, missing exercise).
  `DeloadAdviceTests` checks the same routine in Today, Plan, Workout and the AI context with recent and stale
  history. Each surface requires an eligible exposure in the last 28 days for a current stall.

Finish line: outside `Analytics`, `StallDetection.status` has no callers and `ProgressionSettings(for:)` only
compares with defaults.

### 4. Readiness and the deload recommendation

- [x] `ReadinessAssessment` (history window and the readiness call) and `DeloadAssessment` (in progress, proposal or
  break to confirm, with `TrainingRecord` as its input) live in `TrainingServices`. `TodayModel` and `DeloadAdvice`
  only format them. The history window now always covers the 7 days the recovery signals judge plus their full
  baseline; without cycle tracking it used to stop at 60 days.
- [x] `SourceReader.dailyMetricsBySource` keeps the AI context's documented rows per day and source (task 1 had
  merged them, which dropped Apple Watch SDNN on days with Garmin HRV).
- [x] A `TrainingRecord` loader in `TrainingServices` that reads, for a day, the year of sessions, exercises,
  settings, routines, runs, watch recordings, merged metrics, the week's check-ins, walks and the cycle context.
  `TodayModel` and `AskAIModel` use it; `AppContainer` passes `AskAIModel` the activity and cycle sources it lacks.
  Today and Plan use the same completion criterion for `DeloadDetection`. The Assistant preserves the selected
  export period while it assesses Today over the full baseline.
- [x] Give the AI context pack the same readiness and deload answers Today shows: an optional `today` field
  (readiness level and reasons, deload state and signals, as rule names), documented in `docs/ai-exchange.md`
  (optional field, version stays 1). `AIExchange` may depend on `TrainingServices`.
- [x] Distinct names for the per-reading and 7-day-trend HRV counts (`RecoveryTrend.hrvLowDays` and its text);
  Today calls the deload signal the 7-day HRV average.

Finish line: the AI context and Today state the same readiness level and deload proposal for the same day.

### 5. Guard the boundary

- [x] Add a check (`scripts/check-repo.py`) that fails when a file under
  `Packages/OverreachCore/Sources/Presentation` calls `.runs(from`, `.dailyMetrics(in`, `DeloadDetection.`,
  `DeloadAdvisor.`, `StallDetection.status` or `ReadinessRules.readiness`.
- [x] Mark ADR-0035 accepted and add `TrainingServices` to the layout and dependency rules in `AGENTS.md`.

Finish line: the check passes on `main` and fails on a test file that breaks the rule.
