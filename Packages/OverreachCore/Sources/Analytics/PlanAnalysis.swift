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
        let lastRecovery = RecoveryHistory.lastRecovery(
            deloads: profile.deloads, detected: deloads, before: today, calendar: calendar
        )
        let deloadAge = lastRecovery.map { PlanReviewer.days(from: $0.lastDay, to: today, calendar: calendar) }

        let stalled = LiftStatus.assessAll(
            index: index, exercises: exercises, stored: settings, routines: routines, now: now
        ).filter(\.isStalled).count

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
