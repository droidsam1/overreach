import Domain
import Foundation

/// Evidence behind warm-up suggestions. Keys match entries in `docs/evidence.md` (ADR-0012).
public enum WarmUpEvidence {
    /// A warm-up improved performance in most outcomes studied (Fradkin et al. 2010); adding easy cardio before
    /// specific sets raised leg-press 1RM (Abad et al. 2011), with null results elsewhere (Ribeiro et al. 2014).
    public static let general = EvidenceReference(key: "warm-up-general", level: .moderate)
    /// Low-volume specific sets that reach about 80 % of the working load beat light-only warm-ups (Ribeiro et al.
    /// 2020; Viveiros et al. 2024); mixed findings overall (Ribeiro et al. 2021, systematic review).
    public static let specific = EvidenceReference(key: "warm-up-specific", level: .moderate)
    /// Number of steps, percentages, reps and rounding: 1RM-testing practice and coaching defaults.
    public static let ramp = EvidenceReference(key: "warm-up-ramp", level: .heuristic)
}

/// A suggested warm-up set: lighter than the working sets and not counted for progress or volume.
public struct WarmUpSet: Hashable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

/// Specific warm-up sets before the working sets (`docs/evidence.md`: `warm-up-specific`, `warm-up-ramp`).
///
/// The ramp ends at about 80–90 % of the working load with few reps, so the first working set starts ready but not
/// tired. Heavier work gets more steps. Muscles already worked earlier in the session get only the last step.
public enum WarmUpPrescription {
    /// How heavy the working sets are, from their reps and target RPE.
    public enum Intensity: Sendable {
        /// About 80 % of 1RM or more (e.g. 5 reps at RPE 8).
        case heavy
        /// About 65–80 % of 1RM (typical hypertrophy work).
        case moderate
        /// Under about 65 % of 1RM (15+ reps).
        case light
    }

    /// Weight of an empty Olympic barbell, the lightest barbell warm-up.
    public static let barKg = 20.0

    public static func intensity(reps: Int, targetRPE: Double) -> Intensity {
        let fraction = LoadPrescription.fractionOfOneRepMax(reps: reps, rpe: targetRPE) ?? 0.75
        if fraction >= 0.8 { return .heavy }
        return fraction >= 0.65 ? .moderate : .light
    }

    /// Steps as (fraction of the working load, reps).
    static func steps(for intensity: Intensity, primed: Bool) -> [(fraction: Double, reps: Int)] {
        let ramp: [(fraction: Double, reps: Int)] = switch intensity {
        case .heavy: [(0.4, 5), (0.6, 3), (0.8, 2), (0.9, 1)]
        case .moderate: [(0.5, 6), (0.8, 4)]
        case .light: [(0.6, 6)]
        }
        guard primed else { return ramp }
        // Already warm: one set close to the working load is enough.
        return [ramp.last { $0.fraction <= 0.8 } ?? ramp[0]]
    }

    /// Warm-up sets for working sets of `reps` at `targetRPE` with `workingWeightKg`, rounded to `incrementKg` and
    /// never below the empty bar for barbell lifts. Empty without a load (bodyweight) or when the steps would not be
    /// lighter than the working load.
    public static func sets(
        workingWeightKg: Double, reps: Int, targetRPE: Double, equipment: Equipment, incrementKg: Double,
        primed: Bool
    ) -> [WarmUpSet] {
        guard workingWeightKg > 0, equipment != .bodyweight else { return [] }
        let step = incrementKg > 0 ? incrementKg : 1
        let minimum = equipment == .barbell ? barKg : step
        var result: [WarmUpSet] = []
        for (fraction, stepReps) in steps(for: intensity(reps: reps, targetRPE: targetRPE), primed: primed) {
            let weight = max(LoadPrescription.round(workingWeightKg * fraction, toIncrement: step), minimum)
            guard weight > (result.last?.weightKg ?? 0) + 0.001, weight < workingWeightKg - 0.001 else { continue }
            result.append(WarmUpSet(weightKg: weight, reps: min(stepReps, max(1, reps))))
        }
        return result
    }
}
