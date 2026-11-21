import Domain
import Foundation

/// Training history indexed by exercise, built once in a single pass so analyses don't rescan every session
/// for every exercise and every session (which made the Plan quadratic in the number of sessions).
///
/// Exposures match `ExerciseExposure.history(of:in:)`: one per session per exercise, oldest first.
public struct ExposureIndex: Sendable {
    /// Sessions sorted by start date.
    public let sessions: [StrengthSession]
    private let byExercise: [UUID: [ExerciseExposure]]
    private let progressionByExercise: [UUID: [ExerciseExposure]]
    private let lastProgressionSession: [UUID: Int]

    /// How many previous exposures give the e1RM reference used to classify a set's focus.
    public static let referenceExposures = 6

    public init(sessions: [StrengthSession]) {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        var setsByExercise: [UUID: [WorkoutSet]] = [:]
        var progressionSets: [UUID: [WorkoutSet]] = [:]
        var byExercise: [UUID: [ExerciseExposure]] = [:]
        var progressionByExercise: [UUID: [ExerciseExposure]] = [:]
        var lastProgressionSession: [UUID: Int] = [:]
        for (index, session) in sorted.enumerated() {
            setsByExercise.removeAll(keepingCapacity: true)
            progressionSets.removeAll(keepingCapacity: true)
            var order: [UUID] = []
            for entry in session.entries {
                if setsByExercise[entry.exerciseID] == nil { order.append(entry.exerciseID) }
                setsByExercise[entry.exerciseID, default: []] += entry.sets
                if entry.countsForProgression { progressionSets[entry.exerciseID, default: []] += entry.sets }
            }
            for exerciseID in order {
                let exposure = ExerciseExposure(date: session.startedAt, sets: setsByExercise[exerciseID] ?? [])
                if !exposure.sets.isEmpty { byExercise[exerciseID, default: []].append(exposure) }
                let progression = ExerciseExposure(date: session.startedAt, sets: progressionSets[exerciseID] ?? [])
                if !progression.sets.isEmpty {
                    progressionByExercise[exerciseID, default: []].append(progression)
                    lastProgressionSession[exerciseID] = index
                }
            }
        }
        self.sessions = sorted
        self.byExercise = byExercise
        self.progressionByExercise = progressionByExercise
        self.lastProgressionSession = lastProgressionSession
    }

    /// Exercises with at least one exposure that counts for progression.
    public var progressionExerciseIDs: Dictionary<UUID, [ExerciseExposure]>.Keys { progressionByExercise.keys }

    /// Exposures that count for progression (unfinished exercises left out), oldest first: the history targets
    /// and stalls are judged on, the same as `ExerciseExposure.history(of:in:)`.
    public func progressionExposures(of exerciseID: UUID) -> [ExerciseExposure] {
        progressionByExercise[exerciseID] ?? []
    }

    /// The latest session in which `exerciseID` counted for progression.
    public func lastProgressionSession(of exerciseID: UUID) -> StrengthSession? {
        lastProgressionSession[exerciseID].map { sessions[$0] }
    }

    /// Exercises with at least one exposure.
    public var exerciseIDs: Dictionary<UUID, [ExerciseExposure]>.Keys { byExercise.keys }

    /// Exposures of `exerciseID`, oldest first.
    public func exposures(of exerciseID: UUID) -> [ExerciseExposure] {
        byExercise[exerciseID] ?? []
    }

    /// Exposures of `exerciseID` strictly before `date`, oldest first.
    public func exposures(of exerciseID: UUID, before date: Date) -> ArraySlice<ExerciseExposure> {
        let all = exposures(of: exerciseID)
        return all[..<Self.firstIndex(in: all, notBefore: date)]
    }

    /// The e1RM reference for sets of `exerciseID` done at `date`: the best estimate over the last
    /// `referenceExposures` exposures before `date` and `current` itself.
    public func referenceOneRepMax(for exerciseID: UUID, at date: Date, current: ExerciseExposure) -> Double? {
        let previous = exposures(of: exerciseID, before: date).suffix(Self.referenceExposures)
        return (previous + [current]).compactMap(\.bestEstimatedOneRepMax).max()
    }

    /// Binary search: index of the first exposure on or after `date`.
    private static func firstIndex(in exposures: [ExerciseExposure], notBefore date: Date) -> Int {
        var low = 0
        var high = exposures.count
        while low < high {
            let middle = (low + high) / 2
            if exposures[middle].date < date { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
