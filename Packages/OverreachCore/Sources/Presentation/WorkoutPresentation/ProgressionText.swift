import Analytics
import Domain
import Foundation
import PresentationKit

// Plain-language descriptions of engine output for the logger. Every line names its evidence level.

extension ProgressionReason {
    var text: String {
        switch self {
        case .noHistory:
            L10n.text("No history yet: pick a weight you could lift for a couple more reps.")
        case let .topOfRangeReached(reps):
            L10n.format("All sets reached {1} reps: add load and restart at the bottom of the range.", reps)
        case .addRepsBeforeLoad:
            L10n.text("Add a rep where you can before adding load.")
        case .belowRangeTwice:
            L10n.text("Below the rep range twice at this load: step back one increment.")
        case .allRepsCompleted:
            L10n.text("All reps completed: add load.")
        case let .repeatAfterMiss(misses):
            L10n.format("Missed {1} time(s) at this load: repeat it.", misses)
        case let .resetAfterMisses(misses):
            L10n.format("Missed {1} times in a row: reset about {2} lower and build back up.", misses, "10 %")
        case let .nextRepBlock(reps):
            L10n.format("Next block of the cycle: {1} reps.", reps)
        case let .loadFromEstimatedOneRepMax(estimate, percent):
            L10n.format(
                "Load from your estimated 1RM ({1} kg) at {2}.",
                estimate.formatted(.number.precision(.fractionLength(1))),
                percent.formatted(.number.precision(.fractionLength(0))) + " %"
            )
        case .noLoadIncrementAvailable:
            L10n.text("Top of the range without a load step: add external load or a harder variation.")
        }
    }
}

extension StallSuggestion {
    var text: String {
        switch self {
        case let .microload(increment):
            L10n.format("Use smaller jumps ({1} kg).", increment.formatted())
        case .switchToDoubleProgression:
            L10n.text("Switch to a rep range (double progression).")
        case .changeRepRange:
            L10n.text("Change the rep range for a few weeks.")
        case let .addSet(weekly):
            L10n.format(
                "Add a set: {1} weekly sets is on the low side.",
                weekly.formatted(.number.precision(.fractionLength(0)))
            )
        case let .removeSet(weekly):
            L10n.format(
                "Remove a set: {1} weekly sets is on the high side.",
                weekly.formatted(.number.precision(.fractionLength(0)))
            )
        case let .swapVariation(weeks):
            L10n.format("Swap to a close variation for {1}–{2} weeks.", weeks.lowerBound, weeks.upperBound)
        case let .deloadLift(reduction):
            L10n.format("Deload this lift for a week (−{1}).", (reduction * 100).formatted() + " %")
        }
    }
}

extension ExerciseStatus {
    var text: String? {
        switch self {
        case .notEnoughData: nil
        case .progressing: L10n.text("Progressing")
        case .holding: L10n.text("Holding")
        case .stalled: L10n.text("Stalled")
        }
    }
}
