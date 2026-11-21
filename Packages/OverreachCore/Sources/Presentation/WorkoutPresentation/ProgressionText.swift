import Analytics
import Domain
import Foundation
import PresentationKit

// Plain-language descriptions of engine output for the logger. Every line names its evidence level.

/// The numbers a reason refers to: today's target and the scheme behind it.
struct ReasonContext {
    let target: ExerciseTarget
    let scheme: ProgressionScheme
    let format: Format
    var effortScale = EffortScale.rpe

    /// "75 kg", or "–" without a load (no history yet).
    var weight: String { target.sets.first?.weightKg.map(format.kilograms) ?? "–" }

    /// "9" when every set has the same reps, otherwise "10/10/9".
    var reps: String {
        let reps = target.sets.map(\.reps)
        guard let first = reps.first else { return "–" }
        return reps.allSatisfy { $0 == first } ? String(first) : reps.map(String.init).joined(separator: "/")
    }

    var rpe: Double { target.sets.first?.targetRPE ?? scheme.targetRPE }

    /// The rep range of a double progression.
    var range: ClosedRange<Int>? {
        guard case let .doubleProgression(_, minReps, maxReps, _) = scheme else { return nil }
        return min(minReps, maxReps)...max(minReps, maxReps)
    }

    /// `false` when the exercise has no load increment, so the target cannot add weight.
    var canAddLoad: Bool { !target.reasons.contains(.noLoadIncrementAvailable) }
}

extension ReasonContext {
    func topOfRangeReached(_ reps: Int) -> String {
        guard canAddLoad else { return L10n.format("Last time every set reached {1} reps.", reps) }
        return L10n.format(
            "Today: go up to {1} and start again at {2} reps. Last time every set reached {3}.", weight, self.reps, reps
        )
    }

    func addRepsBeforeLoad() -> String {
        guard let range else { return L10n.format("Today: try {1} reps with {2}.", reps, weight) }
        return L10n.format(
            "Today: try {1} reps with {2}. When every set reaches {3} reps, the weight goes up.",
            reps, weight, range.upperBound
        )
    }

    func belowRangeTwice() -> String {
        let minimum = range?.lowerBound ?? target.sets.first?.reps ?? 0
        return L10n.format(
            "Today: drop to {1} and aim for {2} reps. The last two times, some sets fell short of {3} with the "
                + "previous weight.",
            weight, reps, minimum
        )
    }

    func allRepsCompleted() -> String {
        guard canAddLoad else { return L10n.text("Last time you completed every rep.") }
        return L10n.format("Today: go up to {1}. Last time you completed every rep.", weight)
    }
}

extension ProgressionReason {
    /// What the reason asks for today, with the numbers of the target.
    func instruction(_ context: ReasonContext) -> String {
        let format = context.format
        switch self {
        case .noHistory:
            return L10n.format(
                "First time: choose a weight for {1} reps that leaves about {2} more in reserve ({3}).",
                context.reps, format.number(max(0, 10 - context.rpe)),
                context.effortScale.text(rpe: context.rpe, format: format)
            )
        case .repeatBaseline:
            return L10n.text("Use your last session's working sets as today's starting point.")
        case .repeatWithoutEffort:
            return L10n.text("Repeat today's target and log how many reps you had left to guide the next session.")
        case .repeatAfterHighEffort:
            return L10n.text(
                "Use the last session as a starting point. Do fewer reps or use less weight if you need more "
                    + "reps in reserve."
            )
        case .repeatBeforeLoadJump:
            return L10n.text(
                "Keep the last load. A smaller weight increment in exercise settings can help you progress."
            )
        case let .topOfRangeReached(reps):
            return context.topOfRangeReached(reps)
        case .addRepsBeforeLoad:
            return context.addRepsBeforeLoad()
        case .belowRangeTwice:
            return context.belowRangeTwice()
        case .allRepsCompleted:
            return context.allRepsCompleted()
        case .repeatAfterMiss:
            return L10n.format(
                "Today: repeat {1} and try to complete every rep. Last time some were missing.", context.weight
            )
        case let .resetAfterMisses(misses):
            return L10n.format(
                "Today: drop to {1}, about {2} less, after {3} sessions in a row with missing reps. Build back up "
                    + "from there.",
                context.weight, "10 %", misses
            )
        case let .nextRepBlock(reps):
            return L10n.format("Today is the {1}-rep block of your cycle.", reps)
        case let .loadFromEstimatedOneRepMax(estimate, percent):
            return L10n.format(
                "Today: {1}, which is {2} of your estimated max ({3}) for {4} reps at {5}.",
                context.weight, format.number(percent, maxFractionDigits: 0) + " %",
                format.kilograms((estimate * 10).rounded() / 10), context.reps,
                context.effortScale.text(rpe: context.rpe, format: format)
            )
        case .noLoadIncrementAvailable:
            return L10n.text("To keep progressing, add external load or switch to a harder variation.")
        case let .deloadWeek(sets, reduction, maximumRPE):
            return L10n.format(
                "Deload week: {1} working sets, about {2} less load and {3} at most, to shed fatigue.",
                sets, format.number(reduction * 100, maxFractionDigits: 0) + " %",
                context.effortScale.text(rpe: maximumRPE, format: format)
            )
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
