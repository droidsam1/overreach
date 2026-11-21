import Analytics
import Foundation

extension StallSuggestion {
    /// The suggestion in plain words, with its reason.
    public var text: String {
        switch self {
        case let .microload(increment):
            L10n.format(
                "Use smaller jumps ({1} kg): you were only 1 rep short, and a smaller step lets you keep adding load.",
                increment.formatted()
            )
        case .switchToDoubleProgression:
            L10n.text(
                "Switch to a rep range (double progression): adding reps before load gives you more small steps to "
                    + "progress."
            )
        case .changeRepRange:
            L10n.text("Change the rep range for a few weeks: a different stimulus often gets progress going again.")
        case let .addSet(weekly):
            L10n.format(
                "Add a set: {1} weekly sets is on the low side for this muscle.",
                weekly.formatted(.number.precision(.fractionLength(0)))
            )
        case let .removeSet(weekly):
            L10n.format(
                "Remove a set: {1} weekly sets is on the high side; fatigue may be holding you back.",
                weekly.formatted(.number.precision(.fractionLength(0)))
            )
        case let .swapVariation(weeks):
            L10n.format(
                "Swap to a close variation for {1}–{2} weeks, then come back: the new movement is easier to progress "
                    + "and keeps the muscles working.",
                weeks.lowerBound, weeks.upperBound
            )
        case let .deloadLift(reduction):
            L10n.format(
                "Deload this lift for a week (−{1}) to shed fatigue, then build back up.",
                (reduction * 100).formatted() + " %"
            )
        }
    }
}
