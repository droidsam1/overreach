import Domain
import Foundation

/// Historical observations drawn from saved strength sessions.
public enum StrengthPerformance {
    public struct RecordedSet: Hashable, Sendable {
        public let sessionID: UUID
        public let exerciseID: UUID
        public let setID: UUID
        public let date: Date
        public let source: DataSourceKind
        public let kind: SetKind
        public let weightKg: Double
        public let reps: Int
        public let rpe: Double?
    }

    public enum Record: Hashable, Sendable {
        case heaviestLoad
        case loadAtReps(Int)
        case repsAtLoad(Double)
        case measuredOneRepMax

        public func value(of set: RecordedSet) -> Double? {
            switch self {
            case .heaviestLoad:
                return set.weightKg
            case let .loadAtReps(reps):
                return set.reps == reps ? set.weightKg : nil
            case let .repsAtLoad(weightKg):
                return StrengthPerformance.sameLoad(set.weightKg, weightKg) ? Double(set.reps) : nil
            case .measuredOneRepMax:
                // A successful local single reported at zero reps in reserve is a recorded maximal effort.
                guard set.source == .app, set.kind != .dropSet, set.reps == 1, set.rpe == 10 else { return nil }
                return set.weightKg
            }
        }
    }

    public struct Estimate: Hashable, Sendable {
        public let set: RecordedSet
        public let weightKg: Double
        public let equationVersion: Int

        public var repsInReserve: Double? {
            self.set.rpe.map { LoadPrescription.repsInReserve(rpe: $0) }
        }
    }

    /// A saved set can lack a completion timestamp (e.g. Strong imports or an addition in the history editor).
    /// The completed session is the source of truth. A draft or a warm-up is never an observation.
    public static func recordedSets(in sessions: [StrengthSession], through now: Date) -> [RecordedSet] {
        sessions.filter { $0.isCompleted(through: now) }.flatMap { session in
            session.entries.flatMap { entry in
                entry.sets.compactMap { set in
                    guard set.isWorking, let weight = set.weightKg, weight.isFinite, weight > 0,
                          let reps = set.reps, reps > 0 else { return nil }
                    return RecordedSet(
                        sessionID: session.id, exerciseID: entry.exerciseID, setID: set.id, date: session.startedAt,
                        source: session.source, kind: set.kind, weightKg: weight, reps: reps, rpe: set.rpe
                    )
                }
            }
        }
    }

    /// Best qualifying set per session, oldest first. Pass sets for a single exercise and source so
    /// recorded weights are compared without changing equipment or assuming matching load conventions.
    public static func records(in sets: [RecordedSet], matching record: Record) -> [RecordedSet] {
        guard let first = sets.first, sets.allSatisfy({
            $0.exerciseID == first.exerciseID && $0.source == first.source
        }) else { return [] }
        let tolerance: Double = if case .repsAtLoad = record { 0 } else { loadToleranceKg }
        return bestInEachSession(sets, tolerance: tolerance, value: record.value)
    }

    /// Returns the best set in the period. For equal values prefer the earliest observation.
    public static func record(in sets: [RecordedSet], matching metric: Record) -> RecordedSet? {
        let observations = records(in: sets, matching: metric)
        let tolerance: Double = if case .repsAtLoad = metric { 0 } else { loadToleranceKg }
        return best(in: observations, tolerance: tolerance, value: metric.value)
    }

    /// One effort-adjusted estimate per session, with the recorded source set and equation version.
    /// Only local sessions use the app's RIR-based RPE scale. The pilot models catalog bench press and
    /// back squat, the two lifts with the smallest reported Epley bias in LeSuer et al. (1997).
    public static func estimatedOneRepMax(in sets: [RecordedSet], exercise: Exercise) -> [Estimate] {
        guard let version = equationVersion(for: exercise) else { return [] }
        let candidates = sets.filter { $0.exerciseID == exercise.id && $0.source == .app }
        let observations = bestInEachSession(candidates, tolerance: 0, value: estimate)
        return observations.compactMap { set in
            estimate(set).map { Estimate(set: set, weightKg: $0, equationVersion: version) }
        }
    }

    public static func equationVersion(for exercise: Exercise) -> Int? {
        guard exercise.equipment == .barbell, !exercise.isCustom else { return nil }
        switch ExerciseCatalog.englishName(of: exercise.id) {
        case "Bench Press (Barbell)", "Squat (Barbell)": return 1
        default: return nil
        }
    }

    /// Match the logger's rep record tolerance, for weights normalized from kg or lb.
    static func sameLoad(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < loadToleranceKg
    }

    private static let loadToleranceKg = 0.001

    private static func estimate(_ set: RecordedSet) -> Double? {
        guard set.kind != .dropSet, (2...6).contains(set.reps),
              let effort = set.rpe, (8...10).contains(effort),
              let value = LoadPrescription.estimatedOneRepMax(weightKg: set.weightKg, reps: set.reps, rpe: effort),
              value.isFinite else { return nil }
        return value
    }

    private static func bestInEachSession(
        _ sets: [RecordedSet], tolerance: Double, value: (RecordedSet) -> Double?
    ) -> [RecordedSet] {
        Dictionary(grouping: sets, by: \.sessionID).values
            .compactMap { best(in: $0, tolerance: tolerance, value: value) }
            .sorted { ($0.date, $0.sessionID.uuidString) < ($1.date, $1.sessionID.uuidString) }
    }

    private static func best(
        in sets: [RecordedSet], tolerance: Double, value: (RecordedSet) -> Double?
    ) -> RecordedSet? {
        let candidates = sets.compactMap { set in value(set).map { (set, $0) } }
        guard let highest = candidates.map(\.1).max() else { return nil }
        return candidates.first { $0.1 == highest || highest - $0.1 < tolerance }?.0
    }
}
