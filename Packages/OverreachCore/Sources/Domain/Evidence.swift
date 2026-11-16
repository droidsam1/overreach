import Foundation

/// How strong the support for a rule is (ADR-0012). Shown with recommendations so the user knows how much
/// weight to give them.
public enum EvidenceLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Meta-analyses, umbrella reviews, or a position stand/consensus built on them.
    case strong
    /// Individual RCTs or meta-analyses with low certainty or mixed findings.
    case moderate
    /// Expert consensus (e.g. Delphi), observational data or mechanistic reasoning.
    case limited
    /// Coaching heuristic without direct research; a sensible default the user can change.
    case heuristic

    private var rank: Int {
        switch self {
        case .strong: 3
        case .moderate: 2
        case .limited: 1
        case .heuristic: 0
        }
    }

    public static func < (lhs: EvidenceLevel, rhs: EvidenceLevel) -> Bool { lhs.rank < rhs.rank }
}

/// A pointer from a rule or a recommendation reason to its entry in `docs/evidence.md`.
public struct EvidenceReference: Hashable, Codable, Sendable {
    /// Stable key of the entry in `docs/evidence.md`, e.g. `"rir-rpe-scale"`.
    public var key: String
    public var level: EvidenceLevel

    public init(key: String, level: EvidenceLevel) {
        self.key = key
        self.level = level
    }
}
