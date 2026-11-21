import Domain
import Foundation

/// A lighter example based on familiar work. `easy-strength-example` documents the coaching defaults.
public struct EasyStrengthAdjustment: Hashable, Sendable {
    public static let evidence = EvidenceReference(key: "easy-strength-example", level: .heuristic)
    public static let familiarityDays = 42
    public static let maximumExercises = 3

    public let referenceSets: Int
    public let referenceReps: ClosedRange<Int>
    public let sets: Int
    public let reps: Int
    public let repsInReserve: Int

    /// Use an observed easy load for the full number of sets. Today's effort still takes precedence.
    public func startingLoad(referenceLoadKg: Double?, recent: [ExerciseExposure]) -> Double? {
        guard let referenceLoadKg, referenceLoadKg.isFinite, referenceLoadKg > 0 else { return nil }
        for exposure in recent.reversed() {
            let weights = exposure.sets.compactMap { set -> Double? in
                guard set.kind == .working, (set.reps ?? 0) >= reps,
                      let rpe = set.rpe, rpe >= 1, rpe <= Double(10 - repsInReserve),
                      let weight = set.weightKg, weight > 0, weight <= referenceLoadKg else { return nil }
                return weight
            }
            if weights.count >= sets { return weights.min() }
        }
        return nil
    }

    public static func suggest(
        referenceReps: [Int], referenceRPE: Double?, recent: ExerciseExposure
    ) -> EasyStrengthAdjustment? {
        let validReferenceReps = referenceReps.filter { $0 > 0 }
        guard let minimum = validReferenceReps.min(), let maximum = validReferenceReps.max(),
              let practicedReps = recent.sets.compactMap(\.reps).max() else { return nil }
        let plannedEffort = referenceRPE.flatMap { $0.isFinite ? $0 : nil } ?? 6
        let effortCeiling = min(6, max(1, plannedEffort))
        return EasyStrengthAdjustment(
            referenceSets: validReferenceReps.count, referenceReps: minimum...maximum,
            sets: min(2, max(1, validReferenceReps.count / 2)), reps: min(minimum, practicedReps),
            repsInReserve: Int((10 - effortCeiling).rounded(.up))
        )
    }
}
