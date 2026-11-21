import Analytics
import Domain
import Foundation
import PresentationKit

/// One line about everyday movement in Today (ADR-0010): context for today's training, never a readiness input.
public struct MovementNote: Hashable, Sendable {
    public let text: String
    public let evidence: String

    /// Notes for today's movement signals, plus an easy walk on a red day. The walk respects the athlete's routine:
    /// with a dog or fixed walks it asks to keep those walks easy instead of adding one.
    static func notes(
        signals: [EverydayMovement.Signal], suggestsRecoveryWalk: Bool, routine: WalkingRoutine, today: CalendarDay,
        format: Format
    ) -> [MovementNote] {
        let minutes = { (value: Double) in format.number(value.rounded(), maxFractionDigits: 0) }
        var notes = signals.map { signal in
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
