/// A suggestion about the distribution of strength work in a plan or in logged history.
public struct MuscleBalanceFinding: Identifiable, Hashable, Sendable {
    public enum Rule: String, Sendable, CaseIterable {
        case noDirectWork, lowVolume, highVolume, veryHighVolume, highSessionVolume
        case lowPullVolume, lowDeltVolume, missingPullPattern, noHamstringWork, laggingMuscle, emptyRegion
    }

    public enum Region: String, Sendable {
        case upper, lower
    }

    public let rule: Rule
    public let muscle: MuscleGroup?
    public let pattern: MovementPattern?
    public let region: Region?
    /// Observed weekly fractional sets, direct sets, or the largest session, according to the rule.
    public let measuredSets: Double?
    public let runningKilometres: Double?
    public let evidence: EvidenceReference

    /// Independent of counts, so dismissals survive new sessions or minor changes to a plan.
    public var id: String {
        [rule.rawValue, muscle?.rawValue, pattern?.rawValue, region?.rawValue].compactMap { $0 }.joined(separator: "-")
    }

    public init(
        rule: Rule, muscle: MuscleGroup? = nil, pattern: MovementPattern? = nil, region: Region? = nil,
        measuredSets: Double? = nil, runningKilometres: Double? = nil, evidence: EvidenceReference
    ) {
        self.rule = rule
        self.muscle = muscle
        self.pattern = pattern
        self.region = region
        self.measuredSets = measuredSets
        self.runningKilometres = runningKilometres
        self.evidence = evidence
    }
}
