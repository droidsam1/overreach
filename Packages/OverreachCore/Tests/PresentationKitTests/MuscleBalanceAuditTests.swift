import Domain
import PresentationKit
import Testing

struct MuscleBalanceAuditTests {
    @Test func personalRolloutSelectsOnlyReviewedRules() {
        let reference = EvidenceReference(key: "muscle-balance-maintenance", level: .heuristic)
        let findings = MuscleBalanceFinding.Rule.allCases.map { MuscleBalanceFinding(rule: $0, evidence: reference) }
        let rows = MuscleBalanceAudit.rows(for: findings)

        #expect(rows.map(\.id) == [
            "highVolume", "veryHighVolume", "highSessionVolume", "missingPullPattern",
            "noHamstringWork", "laggingMuscle", "emptyRegion",
        ])
    }
}
