import Foundation

/// Sex as used for training context. `unspecified` is a valid answer and disables sex-specific logic.
public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case female, male, unspecified
}

/// How (and whether) the menstrual cycle is taken into account (ADR-0009).
public enum CycleTrackingMode: String, Codable, Sendable, CaseIterable {
    /// No cycle data is used.
    case off
    /// Natural cycle: phase is estimated and used as context.
    case naturalCycle
    /// Hormonal contraception: no phase estimate; symptoms are still logged.
    case hormonalContraception
    /// Peri- or post-menopause: no phase estimate; symptoms are still logged.
    case menopause

    /// Whether a cycle phase should be estimated for this mode.
    public var estimatesPhase: Bool { self == .naturalCycle }
}

/// The user's everyday walking habits (ADR-0010). Recommendations adapt to it; they never remove fixed walks.
public struct WalkingRoutine: Hashable, Codable, Sendable {
    public var hasDog: Bool
    public var usualWalksPerDay: Int?
    /// Walks that cannot be skipped, only adjusted (length, pace, route).
    public var walksAreFixed: Bool
    /// Whether an easy jog during a walk is possible (e.g. with the dog).
    public var canRunDuringWalks: Bool
    /// Whether it is fine to do more/shorter or fewer/longer walks.
    public var flexibleSplit: Bool

    public init(
        hasDog: Bool = false,
        usualWalksPerDay: Int? = nil,
        walksAreFixed: Bool = false,
        canRunDuringWalks: Bool = false,
        flexibleSplit: Bool = true
    ) {
        self.hasDog = hasDog
        self.usualWalksPerDay = usualWalksPerDay
        self.walksAreFixed = walksAreFixed
        self.canRunDuringWalks = canRunDuringWalks
        self.flexibleSplit = flexibleSplit
    }
}

/// Who the user is, as far as training logic needs to know. Every field is optional or has a neutral default,
/// so the app works before onboarding is complete.
public struct AthleteProfile: Hashable, Codable, Sendable {
    public var sex: BiologicalSex?
    public var birthYear: Int?
    public var bodyMassKg: Double?
    public var maxHeartRate: Double?
    public var restingHeartRate: Double?
    public var cycleTracking: CycleTrackingMode
    public var walkingRoutine: WalkingRoutine

    public init(
        sex: BiologicalSex? = nil,
        birthYear: Int? = nil,
        bodyMassKg: Double? = nil,
        maxHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        cycleTracking: CycleTrackingMode = .off,
        walkingRoutine: WalkingRoutine = WalkingRoutine()
    ) {
        self.sex = sex
        self.birthYear = birthYear
        self.bodyMassKg = bodyMassKg
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.cycleTracking = cycleTracking
        self.walkingRoutine = walkingRoutine
    }

    /// Whether cycle-aware logic applies: only when the user chose a natural cycle explicitly.
    public var usesCyclePhase: Bool { cycleTracking.estimatesPhase }
}
