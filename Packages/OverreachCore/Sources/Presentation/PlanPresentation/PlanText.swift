import Analytics
import Domain
import Foundation
import PresentationKit

// Plain-language descriptions for the Plan screen. Every line names its evidence level.

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
            return "\(sessions) \(focus.displayName.lowercased()) sessions in a row. Intentional? Declare a block, or vary the focus."
        case let .exerciseFocusMismatch(exerciseID, declared, observed):
            let name = names[exerciseID] ?? "An exercise"
            return "\(name) is set to \(declared.displayName.lowercased()) but trained as \(observed.displayName.lowercased()). "
                + "Adjust its reps and load, or its focus."
        case let .sessionFocusMismatch(_, declared, observed):
            return "A \(declared.displayName.lowercased()) session was trained as \(observed.displayName.lowercased())."
        case let .noHeavyWorkOnPriorityLift(exerciseID, days):
            let name = names[exerciseID] ?? "A priority lift"
            return "\(name): no heavy sets (≤ 6 reps near your max) in \(days) days. 1RM strength needs heavy loads."
        case let .muscleSingleFocus(muscle, focus):
            return "\(muscle.displayName) is only trained for \(focus.displayName.lowercased()). Your goal needs both strength and size."
        case let .lowVolume(muscle, weeklySets):
            let sets = weeklySets.formatted(.number.precision(.fractionLength(1)))
            return "\(muscle.displayName): \(sets) sets/week, below the useful range."
        }
    }
}
