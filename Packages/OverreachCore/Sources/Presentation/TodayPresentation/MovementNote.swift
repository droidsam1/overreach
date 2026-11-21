import Analytics
import Domain
import Foundation
import PresentationKit

/// One line about everyday movement in Today (ADR-0010): context for today's training, never a readiness input.
public struct MovementNote: Hashable, Sendable {
    public let text: String
    public let evidence: String?

    struct Schedule {
        let strength: PlannedStrength?
        let routine: Routine?
        let exercises: [Exercise]
        let runs: [PlannedRun]

        var isRest: Bool {
            let hasRest = (strength != nil && strength?.routineID == nil) || runs.contains { $0.purpose == .rest }
            return hasRest && strength?.routineID == nil && runs.allSatisfy { $0.purpose == .rest }
        }

        var hasLegSession: Bool {
            if runs.contains(where: { $0.purpose != .rest && $0.completion == nil }) { return true }
            guard let routine else { return false }
            return exercises.contains { exercise in
                routine.exerciseIDs.contains(exercise.id)
                    && exercise.primaryMuscles.contains(where: { $0.region == .lower })
            }
        }
    }

    static func walkingSummary(minutes: Double, usual: Double, format: Format) -> MovementNote? {
        guard minutes >= 1 else { return nil }
        let text = L10n.format("Walking today: {1} min. Usually {2} min a day.",
                               format.number(minutes, maxFractionDigits: 0),
                               format.number(usual, maxFractionDigits: 0))
        return MovementNote(text: text, evidence: nil)
    }

    /// Localized movement signals and optional activity advice that respects fixed walks and safety guidance.
    static func notes(
        signals: [EverydayMovement.Signal], suggestsRecoveryWalk: Bool, routine: WalkingRoutine, today: CalendarDay,
        format: Format, suggestActivity: Bool = true, hasLegSession: Bool = false
    ) -> [MovementNote] {
        let minutes = { (value: Double) in format.number(value.rounded(), maxFractionDigits: 0) }
        var notes = signals.compactMap { signal -> MovementNote? in
            guard suggestActivity || signal.walkingSpikeDay != nil else { return nil }
            let text = switch signal {
            case let .walkingSpike(day, walked, usual) where day == today:
                L10n.format(
                    "You have walked {1} min today, {2} min more than usual. "
                        + "Your legs may be more tired for leg work or a run.",
                    minutes(walked), minutes(walked - usual)
                )
            case let .walkingSpike(_, walked, usual):
                L10n.format(
                    "Yesterday you walked {1} min, {2} min more than usual. "
                        + "Your legs may be more tired for leg work or a run.",
                    minutes(walked), minutes(walked - usual)
                )
            case let .stepsFarBelowBaseline(days, average, usual):
                L10n.format(
                    "About {1} steps a day over the last {2} days, well under your usual {3}. "
                        + "Very little daily movement can blunt what you get from training: a walk today helps.",
                    format.number(average, maxFractionDigits: 0), String(days),
                    format.number(usual, maxFractionDigits: 0)
                )
            }
            return MovementNote(text: text, evidence: signal.evidence.level.displayName)
        }
        if hasLegSession, signals.contains(where: { $0.walkingSpikeDay != nil }) {
            let cue = L10n.text("Start with an easy warm-up and check how your legs feel before increasing the effort.")
            notes.append(MovementNote(
                text: cue,
                evidence: MovementEvidence.walkingAboveBaseline.level.displayName
            ))
        }
        if suggestsRecoveryWalk {
            let text = routine.hasDog || routine.walksAreFixed
                ? L10n.text(
                    "Keep your usual walks easy today. "
                        + "Easy movement eases soreness and fatigue a little more than full rest."
                )
                : L10n.text("An easy 20–40 min walk can ease soreness and fatigue a little more than full rest.")
            notes.append(MovementNote(text: text, evidence: MovementEvidence.activeRecovery.level.displayName))
        }
        return notes
    }
}

extension EverydayMovement.Signal {
    var walkingSpikeDay: CalendarDay? {
        if case let .walkingSpike(day, _, _) = self { return day }
        return nil
    }
}
