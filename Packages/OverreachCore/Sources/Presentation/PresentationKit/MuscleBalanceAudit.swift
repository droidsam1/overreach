import Domain

public struct MuscleBalanceRow: Identifiable, Sendable {
    public let id: String
    public let text: String
    public let evidence: EvidenceReference
    public let runningContext: String?

    public var evidenceText: String { L10n.format("Evidence: {1}", evidence.level.displayName) }

    public init(_ finding: MuscleBalanceFinding, format: Format = .init()) {
        id = finding.id
        evidence = finding.evidence
        text = Self.message(for: finding)
        runningContext = finding.runningKilometres.map {
            L10n.format("{1} km run in the analysis period", format.number($0, maxFractionDigits: 1))
        }
    }

    // Each rule has its own wording shared by Plan, Trends and exported context.
    // swiftlint:disable:next cyclomatic_complexity
    private static func message(for finding: MuscleBalanceFinding) -> String {
        let muscle = finding.muscle?.displayName ?? ""
        switch finding.rule {
        case .noDirectWork: return L10n.format("No direct sets for {1}.", muscle)
        case .lowVolume: return L10n.format("Weekly volume for {1} is low.", muscle)
        case .highVolume: return L10n.format("Extra sets for {1} may add little benefit at this weekly volume.", muscle)
        case .veryHighVolume:
            return L10n.format("Weekly volume for {1} is very high. Consider whether the extra sets help.", muscle)
        case .highSessionVolume: return L10n.format("Consider spreading sets for {1} across sessions.", muscle)
        case .lowPullVolume: return L10n.text("Pulling volume is low compared with pushing volume.")
        case .lowDeltVolume: return L10n.format("Consider more direct work for {1} alongside pressing.", muscle)
        case .missingPullPattern:
            return finding.pattern == .verticalPull
                ? L10n.text("Consider including a vertical pull.")
                : L10n.text("Consider including a horizontal pull.")
        case .noHamstringWork: return L10n.text("Quadriceps volume is high with no direct hamstring work.")
        case .laggingMuscle: return L10n.format("Sets for {1} are well below your usual volume across muscles.", muscle)
        case .emptyRegion:
            return finding.region == .upper
                ? L10n.text("No upper-body strength sets.")
                : L10n.text("No lower-body strength sets.")
        }
    }
}

/// Device-local UI choices. Reports and the Assistant reuse the history scope.
public struct MuscleBalanceDismissals: Sendable {
    private let read: @MainActor @Sendable (String) -> Set<String>
    private let save: @MainActor @Sendable (String, Set<String>) -> Void

    public init(
        read: @escaping @MainActor @Sendable (String) -> Set<String> = { _ in [] },
        save: @escaping @MainActor @Sendable (String, Set<String>) -> Void = { _, _ in }
    ) {
        self.read = read
        self.save = save
    }

    @MainActor public func dismiss(_ id: String, in scope: String) {
        save(scope, read(scope).union([id]))
    }

    @MainActor public func visible(_ rows: [MuscleBalanceRow], in scope: String) -> [MuscleBalanceRow] {
        let dismissed = read(scope)
        return rows.filter { !dismissed.contains($0.id) }
    }
}

/// Keep findings off all user surfaces until the history replay in ADR-0047 is reviewed.
public enum MuscleBalanceAudit {
    public static let isReleased = false
    public static let historyScope = "history"
}
