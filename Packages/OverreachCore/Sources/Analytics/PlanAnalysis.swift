import Domain
import Foundation

/// Everything the Plan screen shows, computed in one pure pass so it can run off the main actor.
public struct PlanAnalysis: Hashable, Sendable {
    /// The declared block covering today, or else the last block inferred from the sets.
    public var currentBlock: TrainingBlock?
    public var suggestion: BlockSuggestion
    public var plan: [PlannedBlock]
    public var findings: [BalanceFinding]
    /// Exercises whose progression is stalled (feeds the block suggestion).
    public var stalledLifts: Int
    public var deloads: [DetectedDeload]
    public var weeksSinceDeload: Int?

    /// - Parameters:
    ///   - sessions: Training history (any order); the Plan reads the last year.
    ///   - exercises: Catalog by id, for muscles and default progression settings.
    ///   - settings: Stored per-exercise progression settings; missing ones use the exercise default.
    public static func run(
        profile: AthleteProfile,
        sessions: [StrengthSession],
        exercises: [UUID: Exercise],
        settings: [UUID: ProgressionSettings],
        now: Date,
        runs: [RunActivity] = [],
        routines: [Routine] = [],
        runReadFailed: Bool = false,
        recordings: [RecordedStrengthActivity] = [],
        calendar: Calendar = .current
    ) -> PlanAnalysis {
        let index = ExposureIndex(sessions: sessions)
        let today = CalendarDay(now, calendar: calendar)
        let inferred = BlockAdvisor.inferBlocks(index: index, calendar: calendar)
        let current = FocusBalance.activeDeclaredBlock(in: profile, now: now, calendar: calendar) ?? inferred.last
        let deloads = DeloadDetection.periods(
            sessions: sessions, runs: runs, profile: profile, routines: routines, exercises: exercises,
            settings: settings, runReadFailed: runReadFailed, recordings: recordings, today: today, calendar: calendar
        )
        let lastPlannedDeload = profile.deloads.map {
            $0.start.adding(days: max(1, $0.days) - 1, calendar: calendar)
        }.filter { $0 < today }.max()
        let lastDetectedDeload = deloads.last { !$0.needsConfirmation }?.end
        let lastDeload = [lastPlannedDeload, lastDetectedDeload].compactMap { $0 }.max()
        let deloadAge = lastDeload.map { PlanReviewer.days(from: $0, to: today, calendar: calendar) }

        let stalled = index.exerciseIDs.filter { id in
            let config = settings[id] ?? exercises[id].map { ProgressionSettings(for: $0) }
                ?? ProgressionSettings(incrementKg: 2.5)
            return StallDetection.status(history: index.exposures(of: id), settings: config).isStalled
        }.count

        return PlanAnalysis(
            currentBlock: current,
            suggestion: BlockAdvisor.suggestion(
                goal: profile.goal, current: current, today: today, stalledLifts: stalled, calendar: calendar
            ),
            plan: BlockAdvisor.plan(
                goal: profile.goal, current: current, today: today, recentlyDeloaded: deloadAge.map { $0 <= 7 } ?? false,
                calendar: calendar
            ),
            findings: FocusBalance.findings(
                index: index, exercises: exercises, exerciseSettings: settings, profile: profile, now: now
            ),
            stalledLifts: stalled,
            deloads: deloads,
            weeksSinceDeload: deloadAge.map { $0 / 7 }
        )
    }
}
