import Domain
import Foundation

/// Pure strength-training calculations.
public enum StrengthMetrics {
    /// Estimated one-rep max using the Epley formula: `weight × (1 + reps / 30)`.
    /// Returns the weight itself for a single rep, and `nil` for invalid input.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps > 0 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// Best estimated 1RM among the working sets.
    public static func bestEstimatedOneRepMax(in sets: [WorkoutSet]) -> Double? {
        var best: Double?
        for set in sets where set.isWorking {
            guard let weight = set.weightKg, let reps = set.reps,
                  let estimate = estimatedOneRepMax(weightKg: weight, reps: reps) else { continue }
            best = max(best ?? estimate, estimate)
        }
        return best
    }

    /// Total kg moved (weight × reps) across working sets. Warm-ups are excluded.
    public static func tonnage(of sets: [WorkoutSet]) -> Double {
        var total = 0.0
        for set in sets where set.isWorking {
            guard let weight = set.weightKg, let reps = set.reps else { continue }
            total += weight * Double(reps)
        }
        return total
    }

    /// Effective sets per muscle group in a session.
    ///
    /// A working set counts if its RPE is at least `minimumRPE` (default 6, about 4 reps in reserve), or if it has no
    /// RPE recorded. Hypertrophy falls gradually with distance from failure rather than at a cliff, and strength
    /// barely depends on it, so only clearly easy sets are left out (`ProgressionEvidence.effectiveSetThreshold`).
    /// It adds 1 to each primary muscle and 0.5 to each secondary muscle of the exercise.
    /// Exercises missing from `exercises` are skipped.
    public static func effectiveSets(
        in session: StrengthSession,
        exercises: [UUID: Exercise],
        minimumRPE: Double = 6
    ) -> [MuscleGroup: Double] {
        var result: [MuscleGroup: Double] = [:]
        for entry in session.entries {
            guard let exercise = exercises[entry.exerciseID] else { continue }
            let counted = entry.sets.filter { set in
                guard set.isWorking else { return false }
                guard let rpe = set.rpe else { return true }
                return rpe >= minimumRPE
            }.count
            guard counted > 0 else { continue }
            let sets = Double(counted)
            for muscle in exercise.primaryMuscles {
                result[muscle, default: 0] += sets
            }
            for muscle in exercise.secondaryMuscles where !exercise.primaryMuscles.contains(muscle) {
                result[muscle, default: 0] += sets * 0.5
            }
        }
        return result
    }
}
