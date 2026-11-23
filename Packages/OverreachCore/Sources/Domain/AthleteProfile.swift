import Foundation

/// Sex as used for training context. `unspecified` is a valid answer and disables sex-specific logic.
public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case female, male, unspecified
}

/// A device that records health data. Which ones the person uses decides what the app offers to connect (Apple
/// Health permission, the Garmin setup) and what Today can show.
public enum Wearable: String, Codable, Sendable, CaseIterable {
    case appleWatch, garmin, otherWatch
}

/// A deload week the person accepted: from `start`, for `days` days.
public struct DeloadRecord: Hashable, Codable, Sendable {
    public var start: CalendarDay
    public var days: Int
    /// The athlete accepted the steadier week offered when they reported unusual stress (ADR-0038). Absent in
    /// records written before it and for ordinary deloads.
    public var forLifeStress: Bool?

    public init(start: CalendarDay, days: Int, forLifeStress: Bool? = nil) {
        self.start = start
        self.days = days
        self.forLifeStress = forLifeStress
    }

    /// Whether `day` falls inside the deload.
    public func contains(_ day: CalendarDay, calendar: Calendar = .current) -> Bool {
        day >= start && day < start.adding(days: max(1, days), calendar: calendar)
    }
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
    /// The dog's name, for the "With …?" question. Optional so older backups decode (ADR-0018).
    public var dogName: String?
    public var usualWalksPerDay: Int?
    /// Walks that cannot be skipped, only adjusted (length, pace, route).
    public var walksAreFixed: Bool
    /// Whether an easy jog during a walk is possible (e.g. with the dog).
    public var canRunDuringWalks: Bool
    /// Whether it is fine to do more/shorter or fewer/longer walks.
    public var flexibleSplit: Bool

    public init(
        hasDog: Bool = false,
        dogName: String? = nil,
        usualWalksPerDay: Int? = nil,
        walksAreFixed: Bool = false,
        canRunDuringWalks: Bool = false,
        flexibleSplit: Bool = true
    ) {
        self.hasDog = hasDog
        self.dogName = dogName
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
    /// Current goal; `nil` until the user sets one (the app then assumes `.general`).
    public var goal: TrainingGoal?
    /// Blocks the user declared (newest last). Inferred blocks are computed, not stored.
    public var declaredBlocks: [TrainingBlock]
    /// How the user logs effort. Only the display changes: sets always store RPE.
    public var effortScale: EffortScale
    /// Devices the person said they use (first-run setup). Empty: only the iPhone, or not asked yet.
    public var wearables: Set<Wearable>
    /// Deload weeks the person accepted, oldest first (ADR-0027). The latest resets "weeks since the last deload".
    public var deloads: [DeloadRecord]
    /// A deload proposal was postponed until this day (inclusive).
    public var deloadPostponedUntil: CalendarDay?
    public var deloadDecisions: [DeloadDecision]
    /// Days the person marked as a deliberate rest (ADR-0041). Absent in older backups.
    public var restDays: [CalendarDay]
    /// Counts gaps in recorded training as recovery for the discipline that stopped.
    public var countsBreaksAutomatically: Bool
    /// Swaps and postponements of the strength rotation the person accepted, oldest first (ADR-0044). Absent in
    /// older backups.
    public var rotationAdjustments: [RotationAdjustment]

    public init(
        sex: BiologicalSex? = nil,
        birthYear: Int? = nil,
        bodyMassKg: Double? = nil,
        maxHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        cycleTracking: CycleTrackingMode = .off,
        walkingRoutine: WalkingRoutine = WalkingRoutine(),
        goal: TrainingGoal? = nil,
        declaredBlocks: [TrainingBlock] = [],
        effortScale: EffortScale = .rpe,
        wearables: Set<Wearable> = [],
        deloads: [DeloadRecord] = [],
        deloadPostponedUntil: CalendarDay? = nil,
        deloadDecisions: [DeloadDecision] = [],
        restDays: [CalendarDay] = [],
        countsBreaksAutomatically: Bool = true,
        rotationAdjustments: [RotationAdjustment] = []
    ) {
        self.sex = sex
        self.birthYear = birthYear
        self.bodyMassKg = bodyMassKg
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.cycleTracking = cycleTracking
        self.walkingRoutine = walkingRoutine
        self.goal = goal
        self.declaredBlocks = declaredBlocks
        self.effortScale = effortScale
        self.wearables = wearables
        self.deloads = deloads
        self.deloadPostponedUntil = deloadPostponedUntil
        self.deloadDecisions = deloadDecisions
        self.restDays = restDays
        self.countsBreaksAutomatically = countsBreaksAutomatically
        self.rotationAdjustments = rotationAdjustments
    }

    /// Records an accepted adjustment. Recording the same one again changes nothing; the newest
    /// `RotationAdjustment.keptCount` are kept.
    public mutating func record(_ adjustment: RotationAdjustment) {
        guard !rotationAdjustments.contains(adjustment) else { return }
        rotationAdjustments = Array((rotationAdjustments + [adjustment]).suffix(RotationAdjustment.keptCount))
    }

    public mutating func recordDeloadDecision(_ decision: DeloadDecision) {
        deloadDecisions.removeAll { $0.start == decision.start && $0.discipline == decision.discipline }
        deloadDecisions.append(decision)
    }

    /// Marks `day` as a deliberate rest. Marking it again changes nothing.
    public mutating func logRest(on day: CalendarDay) {
        if !restDays.contains(day) { restDays.append(day) }
    }

    public mutating func undoRest(on day: CalendarDay) {
        restDays.removeAll { $0 == day }
    }

    /// Whether cycle-aware logic applies: only when the user chose a natural cycle explicitly.
    public var usesCyclePhase: Bool { cycleTracking.estimatesPhase }
}

extension AthleteProfile {
    private enum CodingKeys: String, CodingKey {
        case sex, birthYear, bodyMassKg, maxHeartRate, restingHeartRate, cycleTracking, walkingRoutine, goal
        case declaredBlocks, effortScale, wearables, deloads, deloadPostponedUntil, deloadDecisions, restDays
        case countsBreaksAutomatically, rotationAdjustments
    }

    /// Tolerant decoding: fields added in later versions fall back to their defaults, so older stores and
    /// backups keep loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sex: try container.decodeIfPresent(BiologicalSex.self, forKey: .sex),
            birthYear: try container.decodeIfPresent(Int.self, forKey: .birthYear),
            bodyMassKg: try container.decodeIfPresent(Double.self, forKey: .bodyMassKg),
            maxHeartRate: try container.decodeIfPresent(Double.self, forKey: .maxHeartRate),
            restingHeartRate: try container.decodeIfPresent(Double.self, forKey: .restingHeartRate),
            cycleTracking: try container.decodeIfPresent(CycleTrackingMode.self, forKey: .cycleTracking) ?? .off,
            walkingRoutine: try container.decodeIfPresent(WalkingRoutine.self, forKey: .walkingRoutine)
                ?? WalkingRoutine(),
            goal: try container.decodeIfPresent(TrainingGoal.self, forKey: .goal),
            declaredBlocks: try container.decodeIfPresent([TrainingBlock].self, forKey: .declaredBlocks) ?? [],
            effortScale: try container.decodeIfPresent(EffortScale.self, forKey: .effortScale) ?? .rpe,
            // Unknown devices (from a newer version) are dropped, not fatal.
            wearables: Set(
                (try container.decodeIfPresent([String].self, forKey: .wearables) ?? []).compactMap(Wearable.init)
            ),
            deloads: try container.decodeIfPresent([DeloadRecord].self, forKey: .deloads) ?? [],
            deloadPostponedUntil: try container.decodeIfPresent(CalendarDay.self, forKey: .deloadPostponedUntil),
            deloadDecisions: try container.decodeIfPresent([DeloadDecision].self, forKey: .deloadDecisions) ?? [],
            restDays: try container.decodeIfPresent([CalendarDay].self, forKey: .restDays) ?? [],
            countsBreaksAutomatically: try container.decodeIfPresent(Bool.self, forKey: .countsBreaksAutomatically)
                ?? true,
            rotationAdjustments: try container.decodeIfPresent(
                [RotationAdjustment].self, forKey: .rotationAdjustments
            ) ?? []
        )
    }
}

/// How effort is logged and shown. Both are the same scale (RPE = 10 − reps in reserve, `rir-based-rpe`).
public enum EffortScale: String, Codable, Sendable, CaseIterable {
    /// Rate of perceived exertion, 6–10.
    case rpe
    /// Reps in reserve: how many more reps were possible.
    case repsInReserve
}
