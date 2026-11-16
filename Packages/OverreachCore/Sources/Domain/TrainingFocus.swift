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

    public init(kind: Kind, targetDate: CalendarDay? = nil, priorityLifts: [UUID] = []) {
        self.kind = kind
        self.targetDate = targetDate
        self.priorityLifts = priorityLifts
    }
}

/// A period of training with one main focus, declared by the user or inferred from history.
public struct TrainingBlock: Hashable, Codable, Sendable {
    public var focus: TrainingFocus
    public var start: CalendarDay
    public var plannedWeeks: Int?
    /// `true` when the user chose it; `false` when inferred from logged sets.
    public var isDeclared: Bool

    public init(focus: TrainingFocus, start: CalendarDay, plannedWeeks: Int? = nil, isDeclared: Bool) {
        self.focus = focus
        self.start = start
        self.plannedWeeks = plannedWeeks
        self.isDeclared = isDeclared
    }
}
