import Foundation

/// How an exercise progresses from one session to the next (`docs/design/progression-engine.md`).
public enum ProgressionScheme: Hashable, Codable, Sendable {
    /// Rep range: add reps until every set reaches `maxReps`, then add load and restart at `minReps`.
    case doubleProgression(sets: Int, minReps: Int, maxReps: Int, targetRPE: Double)
    /// Fixed sets × reps: add load after a successful session; repeat after a miss; reset −10 % after 3 misses.
    case linearLoad(sets: Int, reps: Int, targetRPE: Double)
    /// Cycle through rep blocks (e.g. 12 → 8 → 5); the load of each block comes from the estimated 1RM.
    case repCycle(sets: Int, repBlocks: [Int], targetRPE: Double)
    /// Target reps at a target RPE; the load comes from the latest estimated 1RM (autoregulated).
    case rpeBased(sets: Int, reps: Int, targetRPE: Double)

    /// 3 × 8–12 at RPE 8 (≈ 2 reps in reserve).
    public static let `default` = ProgressionScheme.doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8)

    public var sets: Int {
        switch self {
        case let .doubleProgression(sets, _, _, _), let .linearLoad(sets, _, _),
             let .repCycle(sets, _, _), let .rpeBased(sets, _, _):
            max(1, sets)
        }
    }

    public var targetRPE: Double {
        switch self {
        case let .doubleProgression(_, _, _, rpe), let .linearLoad(_, _, rpe),
             let .repCycle(_, _, rpe), let .rpeBased(_, _, rpe):
            rpe
        }
    }
}

/// Per-exercise progression configuration chosen by the user (with defaults).
public struct ProgressionSettings: Hashable, Codable, Sendable {
    public var scheme: ProgressionScheme
    /// Smallest load step available for this exercise. 0 means load cannot be added (e.g. bodyweight).
    public var incrementKg: Double
    /// Main lifts weigh more in deload decisions (e.g. squat, bench, deadlift, row, overhead press).
    public var isMainLift: Bool
    /// Declared focus of this exercise. `nil` = inherit from the session/block, or infer from the sets.
    public var focus: TrainingFocus?
    /// Choices made from a logged baseline ask for effort before advancing.
    public var requiresLoggedEffort: Bool?

    public init(
        scheme: ProgressionScheme = .default, incrementKg: Double, isMainLift: Bool = false, focus: TrainingFocus? = nil
    ) {
        self.scheme = scheme
        self.incrementKg = max(0, incrementKg)
        self.isMainLift = isMainLift
        self.focus = focus
    }

    public init(for exercise: Exercise, scheme: ProgressionScheme = .default, isMainLift: Bool = false) {
        self.init(scheme: scheme, incrementKg: Self.defaultIncrement(for: exercise.equipment), isMainLift: isMainLift)
    }

    /// Typical smallest jump per equipment. The user can change it (e.g. microplates).
    public static func defaultIncrement(for equipment: Equipment) -> Double {
        switch equipment {
        case .barbell, .cable, .other: 2.5
        case .dumbbell: 2
        case .machine: 5
        case .kettlebell: 4
        case .bodyweight, .band: 0
        }
    }
}
