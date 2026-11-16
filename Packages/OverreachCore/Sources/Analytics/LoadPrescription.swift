import Domain
import Foundation

/// RPE / reps-in-reserve arithmetic and load rounding.
///
/// Uses the RIR-based RPE scale (RPE = 10 − RIR) and the Epley relation extended with reps in reserve:
/// a set of `r` reps at `RIR` behaves like a set to failure of `r + RIR` reps, so
/// `%1RM = 1 / (1 + (r + RIR) / 30)`. Example: 5 reps @ RPE 8 → 7 reps to failure → ≈ 81 % of 1RM.
/// Evidence: `ProgressionEvidence.rirBasedRPE`, `ProgressionEvidence.estimatedOneRepMax`.
public enum LoadPrescription {
    /// Sets with more reps than this are not used to estimate the 1RM.
    public static let maximumRepsForEstimate = 12
    /// RPE values below this are too far from failure to adjust the estimate reliably; they count as RPE 10.
    public static let minimumReliableRPE = 6.0

    public static func repsInReserve(rpe: Double) -> Double {
        min(10, max(0, 10 - rpe))
    }

    /// Fraction of 1RM that allows `reps` reps at `rpe`.
    public static func fractionOfOneRepMax(reps: Int, rpe: Double) -> Double? {
        guard reps > 0 else { return nil }
        let repsToFailure = Double(reps) + repsInReserve(rpe: rpe)
        if repsToFailure <= 1 { return 1 }
        return 1 / (1 + repsToFailure / 30)
    }

    /// Estimated 1RM of one set. With a reliable RPE the reps in reserve are added; otherwise the set is treated
    /// as taken to failure (a conservative estimate). Returns `nil` for sets above `maximumRepsForEstimate`.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int, rpe: Double?) -> Double? {
        guard weightKg > 0, reps > 0, reps <= maximumRepsForEstimate else { return nil }
        var repsToFailure = Double(reps)
        if let rpe, rpe >= minimumReliableRPE {
            repsToFailure += repsInReserve(rpe: rpe)
        }
        if repsToFailure <= 1 { return weightKg }
        return weightKg * (1 + repsToFailure / 30)
    }

    /// Rounds `weightKg` to the nearest multiple of `incrementKg` (no rounding when the increment is 0).
    public static func round(_ weightKg: Double, toIncrement incrementKg: Double) -> Double {
        guard incrementKg > 0 else { return weightKg }
        return (weightKg / incrementKg).rounded() * incrementKg
    }
}
