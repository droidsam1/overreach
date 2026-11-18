import Analytics
import Domain
import Foundation
import PresentationKit

// Plain-language descriptions for the Plan screen. Every line names its evidence level.

extension BlockReason {
    var text: String {
        switch self {
        case .periodizationHelpsStrength:
            L10n.text("Varying volume and intensity over time improves 1RM strength more than training the same way.")
        case .periodizationOptionalForHypertrophy:
            L10n.text("For muscle growth the periodisation model matters little; volume and effort matter more.")
        case let .blockLengthReached(weeks):
            L10n.format("This block has run for {1} weeks.", weeks)
        case let .stallsInBlock(lifts):
            L10n.format("{1} lifts have stalled in this block.", lifts)
        case let .peakForTargetDate(weeksLeft):
            L10n.format("{1} weeks to your target date: time to peak (heavy, less volume, taper the last week).", weeksLeft)
        case .balanceStrengthAndSize:
            L10n.text("Alternating size and strength blocks covers both goals.")
        }
    }
}

extension BalanceFinding {
    func text(names: [UUID: String]) -> String {
        switch self {
        case let .focusStreak(focus, sessions):
            return L10n.format(
                "{1} {2} sessions in a row. Intentional? Declare a block, or vary the focus.",
                sessions, focus.displayName.lowercased()
            )
        case let .exerciseFocusMismatch(exerciseID, declared, observed):
            return L10n.format(
                "{1} is set to {2} but trained as {3}. Adjust its reps and load, or its focus.",
                names[exerciseID] ?? L10n.text("An exercise"),
                declared.displayName.lowercased(), observed.displayName.lowercased()
            )
        case let .sessionFocusMismatch(_, declared, observed):
            return L10n.format(
                "A {1} session was trained as {2}.", declared.displayName.lowercased(), observed.displayName.lowercased()
            )
        case let .noHeavyWorkOnPriorityLift(exerciseID, days):
            return L10n.format(
                "{1}: no heavy sets (≤ 6 reps near your max) in {2} days. 1RM strength needs heavy loads.",
                names[exerciseID] ?? L10n.text("A priority lift"), days
            )
        case let .muscleSingleFocus(muscle, focus):
            return L10n.format(
                "{1} is only trained for {2}. Your goal needs both strength and size.",
                muscle.displayName, focus.displayName.lowercased()
            )
        case let .lowVolume(muscle, weeklySets):
            return L10n.format(
                "{1}: {2} sets/week, below the useful range.",
                muscle.displayName, weeklySets.formatted(.number.precision(.fractionLength(1)))
            )
        }
    }
}
