import Analytics
import Domain
import Foundation

// Plain-language descriptions for the Plan screen. Every line names its evidence level.

extension EvidenceLevel {
    var label: String {
        switch self {
        case .strong: "strong evidence"
        case .moderate: "moderate evidence"
        case .limited: "limited evidence"
        case .heuristic: "coaching heuristic"
        }
    }
}

extension TrainingFocus {
    var title: String {
        switch self {
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .mixed: "Mixed"
        case .endurance: "Endurance"
        }
    }
}

extension TrainingGoal.Kind {
    var title: String {
        switch self {
        case .strength: "Strength"
        case .hypertrophy: "Muscle"
        case .general: "Strength and muscle"
        case .hybrid: "Hybrid (with running)"
        }
    }
}

extension MuscleGroup {
    var title: String { rawValue.capitalized }
}

extension BlockReason {
    var text: String {
        switch self {
        case .periodizationHelpsStrength:
            "Varying volume and intensity over time improves 1RM strength more than training the same way."
        case .periodizationOptionalForHypertrophy:
            "For muscle growth the periodisation model matters little; volume and effort matter more."
        case let .blockLengthReached(weeks):
            "This block has run for \(weeks) weeks."
        case let .stallsInBlock(lifts):
            "\(lifts) lifts have stalled in this block."
        case let .peakForTargetDate(weeksLeft):
            "\(weeksLeft) weeks to your target date: time to peak (heavy, less volume, taper the last week)."
        case .balanceStrengthAndSize:
            "Alternating size and strength blocks covers both goals."
        }
    }
}

extension BalanceFinding {
    func text(names: [UUID: String]) -> String {
        switch self {
        case let .focusStreak(focus, sessions):
            return "\(sessions) \(focus.title.lowercased()) sessions in a row. Intentional? Declare a block, or vary the focus."
        case let .exerciseFocusMismatch(exerciseID, declared, observed):
            let name = names[exerciseID] ?? "An exercise"
            return "\(name) is set to \(declared.title.lowercased()) but trained as \(observed.title.lowercased()). "
                + "Adjust its reps and load, or its focus."
        case let .sessionFocusMismatch(_, declared, observed):
            return "A \(declared.title.lowercased()) session was trained as \(observed.title.lowercased())."
        case let .noHeavyWorkOnPriorityLift(exerciseID, days):
            let name = names[exerciseID] ?? "A priority lift"
            return "\(name): no heavy sets (≤ 6 reps near your max) in \(days) days. 1RM strength needs heavy loads."
        case let .muscleSingleFocus(muscle, focus):
            return "\(muscle.title) is only trained for \(focus.title.lowercased()). Your goal needs both strength and size."
        case let .lowVolume(muscle, weeklySets):
            let sets = weeklySets.formatted(.number.precision(.fractionLength(1)))
            return "\(muscle.title): \(sets) sets/week, below the useful range."
        }
    }
}
