import Domain

/// Evidence behind the progression engine. Keys match entries in `docs/evidence.md` (ADR-0012).
public enum ProgressionEvidence {
    /// Load progression and rep progression give similar hypertrophy and strength (Plotkin et al. 2022).
    public static let loadOrRepProgression = EvidenceReference(key: "progression-load-or-reps", level: .moderate)
    /// Hypertrophy improves closer to failure; strength similar across a wide RIR range (Robinson et al. 2024).
    public static let proximityToFailure = EvidenceReference(key: "proximity-to-failure", level: .strong)
    /// RPE = 10 − reps in reserve; load at a given reps × RPE from the estimated 1RM (Zourdos et al. 2016).
    public static let rirBasedRPE = EvidenceReference(key: "rir-based-rpe", level: .moderate)
    /// Autoregulated and percentage-based load prescription give similar strength gains (Hickmott et al. 2022).
    public static let autoregulation = EvidenceReference(key: "autoregulation-load", level: .moderate)
    /// e1RM from sets of ≤ 12 reps; RIR estimates get less accurate in high-rep sets (Halperin et al. 2022).
    public static let estimatedOneRepMax = EvidenceReference(key: "e1rm-estimation", level: .limited)
    /// Weekly volume has a dose-response with diminishing returns; fractional sets fit best (Pelland et al.).
    public static let volumeDoseResponse = EvidenceReference(key: "volume-dose-response", level: .strong)
    /// Deload definition and design principles from expert consensus (Bell et al. 2023, Delphi).
    public static let deloadDesign = EvidenceReference(key: "deload-design", level: .limited)
    /// A 1-week training break mid-programme reduced strength gains, no effect on hypertrophy (Coleman 2024).
    public static let deloadCost = EvidenceReference(key: "deload-cost", level: .moderate)
    /// Stall window, miss counts, resets, microloading, variation swaps: coaching defaults.
    public static let stallHeuristics = EvidenceReference(key: "stall-heuristics", level: .heuristic)
    /// Rising RPE at the same load and reps as a fatigue signal.
    public static let rpeCreep = EvidenceReference(key: "rpe-creep", level: .heuristic)
    /// Last week's load against the usual week (uncoupled); a weak signal, never an injury-risk measure.
    public static let weeklyLoadChange = EvidenceReference(key: "weekly-load-change", level: .heuristic)
    /// Trained lifters deload about every 5–6 weeks, reducing volume and load (Rogerson et al. 2024, survey).
    public static let deloadPractice = EvidenceReference(key: "deload-practice", level: .limited)
}
