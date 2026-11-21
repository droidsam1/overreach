import Analytics
import Domain
import Foundation
import PresentationKit

/// A setting change that follows a stall suggestion, confirmed before it is saved.
public struct LiftChange: Hashable, Sendable {
    /// Button title: "Use 1.25 kg jumps".
    public let title: String
    /// What changes, shown before saving.
    public let confirmation: String
}

/// One current lift that stopped progressing, with one concrete next step (deloads task 6).
public struct LiftToUnblockRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    /// "No progress since 12 Sep (best 82.5 kg × 5)".
    public let since: String
    /// The first suggestion, with its evidence for the detail.
    public let nextStep: ExplainedLine?
    /// The other suggestions, advice only.
    public let otherSteps: [ExplainedLine]
    /// The change behind the next step, when it maps to a setting and has not been applied yet.
    public let change: LiftChange?
    /// Why a scheme suggestion cannot be applied here, or that it was applied.
    public let note: String?

    init(lift: StalledLift, name: String, applied: Bool, calendar: Calendar, format: Format = .init()) {
        id = lift.exerciseID
        self.name = name
        let explanation = lift.explanation
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
            .locale(format.locale)
        let date = explanation.stalledSince.formatted(style)
        if let weight = explanation.bestSet.weightKg, let reps = explanation.bestSet.reps {
            since = L10n.format(
                "No progress since {1} (best {2} × {3})", date, format.kilograms(weight),
                format.number(Double(reps), maxFractionDigits: 0)
            )
        } else {
            since = L10n.format("No progress since {1}", date)
        }
        nextStep = lift.nextStep.map { ExplainedLine(text: $0.text, evidence: $0.evidence) }
        otherSteps = explanation.suggestions.dropFirst().map { ExplainedLine(text: $0.text, evidence: $0.evidence) }

        let changed = lift.nextStep.flatMap(lift.applying)
        if applied {
            change = nil
            note = L10n.text("Changed. Give it three sessions before judging it.")
        } else if let step = lift.nextStep, let changed {
            change = Self.change(step, to: changed, name: name, format: format)
            note = nil
        } else if lift.schemeFromRoutine, let step = lift.nextStep,
                  step.scheme(replacing: lift.settings.scheme) != nil {
            change = nil
            note = L10n.text("This lift's sets and reps come from its routine. Change them in the routine.")
        } else {
            change = nil
            note = nil
        }
    }

    private static func change(
        _ step: StallSuggestion, to settings: ProgressionSettings, name: String, format: Format
    ) -> LiftChange? {
        switch (step, settings.scheme) {
        case (.microload, _):
            let step = format.kilograms(settings.incrementKg)
            return LiftChange(
                title: L10n.format("Use {1} jumps", step),
                confirmation: L10n.format("{1} will add {2} at a time from its next session.", name, step)
            )
        case let (.switchToDoubleProgression, .doubleProgression(sets, minReps, maxReps, _)):
            return LiftChange(
                title: L10n.format("Switch to {1}–{2} reps", minReps, maxReps),
                confirmation: L10n.format(
                    "{1} will use {2} sets of {3}–{4} reps from its next session, adding reps before load.",
                    name, sets, minReps, maxReps
                )
            )
        case let (.changeRepRange, .doubleProgression(sets, minReps, maxReps, _)):
            return LiftChange(
                title: L10n.format("Change to {1}–{2} reps", minReps, maxReps),
                confirmation: L10n.format(
                    "{1} will use {2} sets of {3}–{4} reps from its next session.", name, sets, minReps, maxReps
                )
            )
        default:
            return nil
        }
    }
}
