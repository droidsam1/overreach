import Analytics
import Domain
import Foundation
import PresentationKit

/// How the deload plan changes one concrete session: the last time each exercise of that workout was done, and the
/// lighter version (`DeloadPlan.standard`, `deload-practice`).
public struct DeloadSessionPreview: Hashable, Sendable {
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        public let title: String
        /// "Last time · 4 × 6 · 100 kg"
        public let reference: String
        /// "Deload · 2 × 6 · 90 kg"
        public let deload: String
    }

    /// "Next in your rotation: Workout A"
    public let heading: String
    public let rows: [Row]

    public static let maximumExercises = 6

    static func make(
        heading: String, session: StrengthSession, exercises: [Exercise], settings: [UUID: ProgressionSettings],
        format: Format
    ) -> DeloadSessionPreview? {
        let plan = DeloadPlan.standard
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<UUID> = []
        let rows = session.entries
            .filter { seen.insert($0.exerciseID).inserted }
            .compactMap { entry -> Row? in
                guard let exercise = byID[entry.exerciseID],
                      let exposure = ExerciseExposure.history(of: entry.exerciseID, in: [session]).last
                else { return nil }
                let increment = settings[exercise.id]?.incrementKg ?? ProgressionSettings(for: exercise).incrementKg
                let sets = exposure.setsAtWorkingWeight
                guard let reps = sets.compactMap(\.reps).max() else { return nil }
                let weight = exposure.workingWeightKg
                let count = max(1, Int((Double(exposure.sets.count) * plan.setMultiplier).rounded()))
                let lighter = weight > 0
                    ? LoadPrescription.round(weight * plan.loadMultiplier, toIncrement: increment) : 0
                return Row(
                    id: exercise.id, title: exercise.displayName,
                    reference: L10n.format(
                        "Last time · {1}", text(sets: exposure.sets.count, reps: reps, weight: weight, format: format)
                    ),
                    deload: L10n.format("Deload · {1}", text(sets: count, reps: reps, weight: lighter, format: format))
                )
            }
            .prefix(maximumExercises)
        return rows.isEmpty ? nil : DeloadSessionPreview(heading: heading, rows: Array(rows))
    }

    private static func text(sets: Int, reps: Int, weight: Double, format: Format) -> String {
        let volume = "\(sets) × \(reps)"
        return weight > 0 ? volume + " · " + format.number(weight, maxFractionDigits: 2) + " kg" : volume
    }
}
