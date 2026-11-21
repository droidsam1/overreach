import Domain
import Foundation

/// Where one exercise stands: the settings it is progressed with and whether it is progressing, holding or stalled.
/// The one answer the logger, Plan, the deload advice and the AI context use (ADR-0035).
public struct LiftStatus: Hashable, Sendable {
    public static let recentDays = 28

    public let exerciseID: UUID
    /// Exposures that count for progression, oldest first.
    public let history: [ExerciseExposure]
    public let settings: ProgressionSettings
    public let status: ExerciseStatus
    public let trainedRecently: Bool
    public let facts: StallFacts?

    public var isStalled: Bool { status.isStalled }
    public var lastTrained: Date? { history.last?.date }

    /// The status of `history` judged with `settings` (the logger passes the settings of the session in progress).
    public static func assess(
        exerciseID: UUID, history: [ExerciseExposure], settings: ProgressionSettings, now: Date,
        lookbackDays: Int = recentDays
    ) -> Self {
        let earliest = now.addingTimeInterval(-ProgressionTargets.historyWindow)
        let recentHistory = history.filter { (earliest...now).contains($0.date) }
        let trainedRecently = recentHistory.last.map {
            now.timeIntervalSince($0.date) <= Double(lookbackDays) * 86_400
        } ?? false
        let assessment = trainedRecently ? StallDetection.assessment(history: recentHistory, settings: settings)
            : (.notEnoughData, nil)
        return Self(
            exerciseID: exerciseID, history: recentHistory, settings: settings, status: assessment.status,
            trainedRecently: trainedRecently, facts: assessment.facts
        )
    }

    /// Every exercise trained in `index`, each judged with the settings of the latest session that trained it: its
    /// routine's prescription and the declared focus, as the logger set its targets.
    public static func assessAll(
        index: ExposureIndex, exercises: [UUID: Exercise], stored: [UUID: ProgressionSettings], routines: [Routine],
        now: Date, lookbackDays: Int = recentDays
    ) -> [Self] {
        let routineByID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return index.progressionExerciseIDs.map { id in
            let session = index.lastProgressionSession(of: id)
            let routine = session?.routineID.flatMap { routineByID[$0] }
            let settings = ProgressionTargets.settings(
                for: exercises[id], stored: stored[id], focus: stored[id]?.focus ?? session?.focus ?? routine?.focus,
                prescription: routine?.prescription(for: id)
            )
            return assess(
                exerciseID: id, history: index.progressionExposures(of: id), settings: settings, now: now,
                lookbackDays: lookbackDays
            )
        }
        .sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
    }
}
