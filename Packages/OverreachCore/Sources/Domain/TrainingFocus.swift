import Foundation

/// What a block, session or exercise is mainly trying to develop (ADR-0013, `docs/design/training-focus.md`).
public enum TrainingFocus: String, Codable, Sendable, CaseIterable {
    /// Maximal strength: heavy loads, low reps, long rests.
    case strength
    /// Muscle growth: moderate loads, close to failure, enough volume.
    case hypertrophy
    /// Both, in the same session or week (e.g. heavy top sets + back-off volume).
    case mixed
    /// Local muscular endurance: light loads, high reps, short rests.
    case endurance
}

/// The user's current training goal, which the balance analysis and the block advisor judge against.
public struct TrainingGoal: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Get stronger on the priority lifts (1RM / few-rep strength).
        case strength
        /// Build muscle.
        case hypertrophy
        /// Strength and muscle with no single priority.
        case general
        /// Strength training supporting running (hybrid athlete).
        case hybrid
    }

    public var kind: Kind
    /// Optional date to peak for (e.g. a test day or competition).
    public var targetDate: CalendarDay?
    /// Lifts whose 1RM matters most (e.g. squat, bench, deadlift).
    public var priorityLifts: [UUID]
    public var running: RunningGoal?
    public var nextRun: PlannedRun?

    public init(
        kind: Kind, targetDate: CalendarDay? = nil, priorityLifts: [UUID] = [],
        running: RunningGoal? = nil, nextRun: PlannedRun? = nil
    ) {
        self.kind = kind
        self.targetDate = targetDate
        self.priorityLifts = priorityLifts
        self.running = running
        self.nextRun = nextRun
    }
}

/// A period of training with one main focus, declared by the user or inferred from history.
public struct TrainingBlock: Hashable, Codable, Sendable {
    public var focus: TrainingFocus
    public var start: CalendarDay
    public var plannedWeeks: Int?
    /// `true` when the user chose it; `false` when inferred from logged sets.
    public var isDeclared: Bool
    /// "Strength block"; `nil` for blocks declared without a name.
    public var name: String?
    /// Routines trained in this block, in rotation order (a training plan, issue #34). Empty = no planned sessions.
    public var routineIDs: [UUID]
    /// Planned strength sessions a week; `nil` = one per routine.
    public var sessionsPerWeek: Int?
    /// Weeks added to the block to make up for missed sessions, so the same missed sessions are not counted twice.
    public var extendedWeeks: Int

    public init(
        focus: TrainingFocus, start: CalendarDay, plannedWeeks: Int? = nil, isDeclared: Bool, name: String? = nil,
        routineIDs: [UUID] = [], sessionsPerWeek: Int? = nil, extendedWeeks: Int = 0
    ) {
        self.focus = focus
        self.start = start
        self.plannedWeeks = plannedWeeks
        self.isDeclared = isDeclared
        self.name = name
        self.routineIDs = routineIDs
        self.sessionsPerWeek = sessionsPerWeek
        self.extendedWeeks = extendedWeeks
    }

    /// Sessions a week the plan expects (at least one).
    public var plannedSessionsPerWeek: Int { max(1, sessionsPerWeek ?? routineIDs.count) }

    /// The first day after the block, when its length is known.
    public func end(calendar: Calendar = .current) -> CalendarDay? {
        plannedWeeks.map { start.adding(days: $0 * 7, calendar: calendar) }
    }
}

extension TrainingBlock {
    private enum CodingKeys: String, CodingKey {
        case focus, start, plannedWeeks, isDeclared, name, routineIDs, sessionsPerWeek, extendedWeeks
    }

    /// Tolerant decoding (ADR-0018): blocks saved before plans existed have no name or routines.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            focus: try container.decode(TrainingFocus.self, forKey: .focus),
            start: try container.decode(CalendarDay.self, forKey: .start),
            plannedWeeks: try container.decodeIfPresent(Int.self, forKey: .plannedWeeks),
            isDeclared: try container.decode(Bool.self, forKey: .isDeclared),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            routineIDs: try container.decodeIfPresent([UUID].self, forKey: .routineIDs) ?? [],
            sessionsPerWeek: try container.decodeIfPresent(Int.self, forKey: .sessionsPerWeek),
            extendedWeeks: try container.decodeIfPresent(Int.self, forKey: .extendedWeeks) ?? 0
        )
    }
}
