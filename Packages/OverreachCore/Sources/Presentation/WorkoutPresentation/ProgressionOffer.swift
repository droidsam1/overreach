import Analytics
import Domain
import Foundation
import PresentationKit

/// Content for the optional progression picker in an exercise's logging section.
public struct ProgressionOffer: Hashable, Sendable {
    public struct Option: Identifiable, Hashable, Sendable {
        let choice: FirstProgression.Choice
        public var id: String { choice.strategy.rawValue }
        public let title: String
        public let detail: String
        public let preview: String
    }

    public let lastSession: String
    public let note: String?
    public let options: [Option]

    static func make(
        baseline: ExerciseTarget, choices: [FirstProgression.Choice], effortScale: EffortScale, format: Format
    ) -> Self {
        let options = choices.map { choice in
            let title: String
            let detail: String
            switch choice.strategy {
            case .repetitions:
                title = L10n.text("Add reps first")
                detail = L10n.text("Build up within a rep range, then add weight. A simple starting point.")
            case .load:
                title = L10n.text("Add weight at fixed reps")
                detail = L10n.format("Keep reps fixed and add {1} when you have enough reps in reserve.",
                                    format.weight(choice.settings.incrementKg))
            case .wave:
                title = L10n.text("Alternate heavy and light sessions")
                detail = L10n.text("Cycle through different rep targets with a load estimated for each.")
            }
            return Option(
                choice: choice, title: title, detail: detail,
                preview: L10n.format("Today · {1} · {2}", format.groupedSets(choice.target.sets),
                                     effortScale.text(rpe: choice.settings.scheme.targetRPE, format: format))
            )
        }
        let note = choices.first.flatMap { first -> String? in
            let reason = first.target.reasons.first
            switch reason {
            case .repeatWithoutEffort, .repeatAfterHighEffort:
                let context = ReasonContext(target: first.target, scheme: first.settings.scheme,
                                            format: format, effortScale: effortScale)
                return reason?.instruction(context)
            default:
                return nil
            }
        }
        return Self(lastSession: L10n.format("Last session · {1}", format.groupedSets(baseline.sets)),
                    note: note, options: options)
    }
}
