import Domain
import Foundation

/// A current lift that stopped progressing, with the settings it is judged with (`stall-heuristics`).
/// The shared "Lifts to unblock" finding: Plan shows it now, Recovery & Progress later (#126).
public struct StalledLift: Hashable, Sendable {
    public let explanation: StallExplanation
    /// The settings the lift is progressed with, including a routine's prescription.
    public let settings: ProgressionSettings
    /// What the user stored for this exercise; `nil` while it uses the defaults.
    public let stored: ProgressionSettings?
    /// A routine prescribes the scheme, so a scheme change belongs in that routine, not in the exercise.
    public let schemeFromRoutine: Bool

    public var exerciseID: UUID { explanation.exerciseID }
    /// The first suggestion: the one concrete next step.
    public var nextStep: StallSuggestion? { explanation.suggestions.first }

    /// The stored settings after applying `suggestion`, or `nil` when it is advice only.
    public func applying(_ suggestion: StallSuggestion) -> ProgressionSettings? {
        var result = stored ?? settings
        switch suggestion {
        case let .microload(increment):
            result.incrementKg = increment
        case .switchToDoubleProgression, .changeRepRange:
            guard !schemeFromRoutine, let scheme = suggestion.scheme(replacing: settings.scheme) else { return nil }
            result.scheme = scheme
        case .addSet, .removeSet, .swapVariation, .deloadLift:
            return nil
        }
        return result
    }
}

extension StallSuggestion {
    /// The scheme this suggestion moves to, for the suggestions that change the scheme.
    public func scheme(replacing scheme: ProgressionScheme) -> ProgressionScheme? {
        switch (self, scheme) {
        case let (.switchToDoubleProgression, .linearLoad(sets, reps, rpe)):
            // Same sets, the current reps as the floor: 5 → 5–7, 8 → 8–12.
            let floor = max(1, reps)
            return .doubleProgression(sets: sets, minReps: floor, maxReps: floor + max(2, floor / 2), targetRPE: rpe)
        case let (.changeRepRange, .doubleProgression(sets, minReps, maxReps, rpe)):
            // Heavier when there is room (8–12 → 6–10), lighter otherwise (3–5 → 5–7).
            let shift = minReps - 2 >= 3 ? -2 : 2
            return .doubleProgression(sets: sets, minReps: minReps + shift, maxReps: maxReps + shift, targetRPE: rpe)
        default:
            return nil
        }
    }
}

public enum LiftsToUnblock {
    /// Current lifts that are stalled, the longest-stalled first. A lift not trained in the last 28 days, or outside
    /// the current routines or rotation when they are known, is not listed.
    public static func find(
        index: ExposureIndex, exercises: [UUID: Exercise], stored: [UUID: ProgressionSettings], routines: [Routine],
        currentExerciseIDs: Set<UUID>?, now: Date
    ) -> [StalledLift] {
        let routineByID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return LiftStatus.assessAll(index: index, exercises: exercises, stored: stored, routines: routines, now: now)
            .filter { currentExerciseIDs?.contains($0.exerciseID) ?? true }
            .compactMap { lift -> StalledLift? in
                guard let explanation = lift.stallExplanation else { return nil }
                let routine = index.lastProgressionSession(of: lift.exerciseID)?.routineID.flatMap { routineByID[$0] }
                return StalledLift(
                    explanation: explanation, settings: lift.settings, stored: stored[lift.exerciseID],
                    schemeFromRoutine: routine?.prescription(for: lift.exerciseID) != nil
                )
            }
            .sorted {
                ($0.explanation.stalledSince, $0.exerciseID.uuidString)
                    < ($1.explanation.stalledSince, $1.exerciseID.uuidString)
            }
    }
}
