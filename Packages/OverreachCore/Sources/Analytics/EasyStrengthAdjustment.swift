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
