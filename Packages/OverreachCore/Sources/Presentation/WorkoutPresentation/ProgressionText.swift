import Analytics
import Domain
import Foundation
import PresentationKit

// Plain-language descriptions of engine output for the logger. Every line names its evidence level.

extension ProgressionReason {
    var text: String {
        switch self {
        case .noHistory:
            "No history yet: pick a weight you could lift for a couple more reps."
        case let .topOfRangeReached(reps):
            "All sets reached \(reps) reps: add load and restart at the bottom of the range."
        case .addRepsBeforeLoad:
            "Add a rep where you can before adding load."
        case .belowRangeTwice:
            "Below the rep range twice at this load: step back one increment."
        case .allRepsCompleted:
            "All reps completed: add load."
        case let .repeatAfterMiss(misses):
            "Missed \(misses) time(s) at this load: repeat it."
        case let .resetAfterMisses(misses):
            "Missed \(misses) times in a row: reset about 10 % lower and build back up."
        case let .nextRepBlock(reps):
            "Next block of the cycle: \(reps) reps."
        case let .loadFromEstimatedOneRepMax(estimate, percent):
            "Load from your estimated 1RM (\(estimate.formatted(.number.precision(.fractionLength(1)))) kg) "
                + "at \(percent.formatted(.number.precision(.fractionLength(0)))) %."
        case .noLoadIncrementAvailable:
            "Top of the range without a load step: add external load or a harder variation."
        }
    }
}

extension StallSuggestion {
    var text: String {
        switch self {
        case let .microload(increment):
            "Use smaller jumps (\(increment.formatted()) kg)."
        case .switchToDoubleProgression:
            "Switch to a rep range (double progression)."
        case .changeRepRange:
            "Change the rep range for a few weeks."
        case let .addSet(weekly):
            "Add a set: \(weekly.formatted(.number.precision(.fractionLength(0)))) weekly sets is on the low side."
        case let .removeSet(weekly):
            "Remove a set: \(weekly.formatted(.number.precision(.fractionLength(0)))) weekly sets is on the high side."
        case let .swapVariation(weeks):
            "Swap to a close variation for \(weeks.lowerBound)–\(weeks.upperBound) weeks."
        case let .deloadLift(reduction):
            "Deload this lift for a week (−\((reduction * 100).formatted()) %)."
        }
    }
}

extension ExerciseStatus {
    var text: String? {
        switch self {
        case .notEnoughData: nil
        case .progressing: "Progressing"
        case .holding: "Holding"
        case .stalled: "Stalled"
        }
    }
}

