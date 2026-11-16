import Domain

/// Evidence behind focus-specific prescriptions, classification, balance and block planning (ADR-0013).
public enum FocusEvidence {
    /// Heavy loads (> 60 % 1RM) give larger 1RM gains; hypertrophy is similar across a wide loading range
    /// when sets go close to failure (Schoenfeld et al. 2017; Lopez et al. 2021; Schoenfeld et al. 2021).
    public static let loadingByGoal = EvidenceReference(key: "loading-by-goal", level: .strong)
    /// Rests > 60 s give a small hypertrophy benefit, no appreciable difference beyond ~90 s (Singer et al. 2024).
    public static let restHypertrophy = EvidenceReference(key: "rest-hypertrophy", level: .moderate)
    /// Longer rests (≈ 3 min) favour strength and volume on heavy sets (Schoenfeld et al. 2016).
    public static let restStrength = EvidenceReference(key: "rest-strength", level: .moderate)
    /// Periodised training beats non-periodised for 1RM, not for hypertrophy; undulating ≥ linear for strength in
    /// trained lifters (Moesgaard et al. 2022); linear vs daily undulating similar for hypertrophy (Grgic et al. 2017).
    public static let periodization = EvidenceReference(key: "periodization", level: .strong)
    /// Rep/intensity thresholds that classify a set's focus, and block lengths: coaching heuristics.
    public static let focusHeuristics = EvidenceReference(key: "focus-heuristics", level: .heuristic)
}

/// The default prescription for a focus. Users can change it per exercise.
public struct FocusPrescription: Hashable, Sendable {
    public var focus: TrainingFocus
    public var repRange: ClosedRange<Int>
    public var targetRPE: Double
    /// Typical load as a fraction of 1RM (informative; loads come from the progression engine).
    public var loadRange: ClosedRange<Double>
    /// Suggested rest between working sets, in seconds.
    public var restSeconds: ClosedRange<Int>
    public var defaultScheme: ProgressionScheme
    public var evidence: [EvidenceReference]

    public static func `for`(_ focus: TrainingFocus) -> FocusPrescription {
        switch focus {
        case .strength:
            FocusPrescription(
                focus: .strength, repRange: 1...6, targetRPE: 8, loadRange: 0.80...0.95, restSeconds: 180...300,
                defaultScheme: .rpeBased(sets: 4, reps: 4, targetRPE: 8),
                evidence: [FocusEvidence.loadingByGoal, FocusEvidence.restStrength, ProgressionEvidence.proximityToFailure]
            )
        case .hypertrophy:
            FocusPrescription(
                focus: .hypertrophy, repRange: 6...15, targetRPE: 8.5, loadRange: 0.60...0.85, restSeconds: 90...180,
                defaultScheme: .doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8.5),
                evidence: [FocusEvidence.loadingByGoal, FocusEvidence.restHypertrophy, ProgressionEvidence.proximityToFailure]
            )
        case .mixed:
            FocusPrescription(
                focus: .mixed, repRange: 4...10, targetRPE: 8, loadRange: 0.70...0.88, restSeconds: 120...240,
                defaultScheme: .doubleProgression(sets: 3, minReps: 5, maxReps: 8, targetRPE: 8),
                evidence: [FocusEvidence.loadingByGoal, FocusEvidence.focusHeuristics]
            )
        case .endurance:
            FocusPrescription(
                focus: .endurance, repRange: 15...30, targetRPE: 8, loadRange: 0.40...0.60, restSeconds: 30...90,
                defaultScheme: .doubleProgression(sets: 2, minReps: 15, maxReps: 25, targetRPE: 8),
                evidence: [FocusEvidence.loadingByGoal, FocusEvidence.focusHeuristics]
            )
        }
    }
}
