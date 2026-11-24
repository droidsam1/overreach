import Analytics
import Domain
import Foundation
import PresentationKit

/// A proposed change to the plan, shown under "Up next" (issue #34). The user accepts or ignores it.
public struct PlanCheckRow: Identifiable, Hashable, Sendable {
    public let id: Int
    /// "Plan 2 sessions a week instead of 3."
    public let text: String
    /// Why, with the evidence level: "You did about 2 a week lately. … (strong evidence)".
    public let reason: String
    /// "Plan 2 a week"; `nil` when there is nothing to change in the plan (advice only).
    public let actionTitle: String?
    /// "Learn more" for the reason (ADR-0030); often empty.
    public let readings: [Reading]
    let adjustment: PlanAdjustment
    let block: TrainingBlock
}

/// Today's planned session and the daily assessment that proposes changing it (`DailyRecoveryAction`).
struct PlanToday: Hashable, Sendable {
    /// The routine's name.
    let session: String
    let readiness: Readiness
}

/// Texts of the plan follow-up.
enum PlanFollowUpText {
    /// The signals behind the recovery light, as Today's "Why" words them. Context that never decides the light on its
    /// own is left out.
    static func signalText(_ readiness: Readiness, format: Format) -> String {
        let reasons = readiness.reasons.filter { !$0.isContext && $0 != .missingData }
        let sentences = reasons.map { ReadinessReasonText.text(for: $0, readiness: readiness, format: format) }
        return sentences.isEmpty
            ? L10n.format("Your recovery light is {1} today.", readiness.level.displayName)
            : sentences.joined(separator: " ")
    }

    /// "This week: 1 of 3 sessions".
    static func weekProgress(_ review: PlanReview) -> String? {
        review.currentWeek.map { L10n.format("This week: {1} of {2} sessions", $0.done, $0.planned) }
    }

    /// - Parameters:
    ///   - today: today's planned session and the assessment behind a recovery proposal.
    static func rows(_ review: PlanReview, today: PlanToday? = nil, format: Format = Format()) -> [PlanCheckRow] {
        let blockName = review.block.name ?? review.block.focus.displayName
        return review.adjustments.enumerated().map { index, adjustment in
            let texts = texts(adjustment, blockName: blockName, today: today, format: format)
            return PlanCheckRow(
                id: index, text: texts.text,
                reason: "\(texts.reason) (\(adjustment.evidence.level.displayName))",
                actionTitle: texts.action, readings: FurtherReading.readings(for: adjustment.evidence),
                adjustment: adjustment, block: review.block
            )
        }
    }

    private struct Texts {
        let text: String
        let reason: String
        let action: String?

        init(_ text: String, _ reason: String, _ action: String?) {
            self.text = text
            self.reason = reason
            self.action = action
        }
    }

    private static func texts(
        _ adjustment: PlanAdjustment, blockName: String, today: PlanToday?, format: Format
    ) -> Texts {
        switch adjustment {
        case let .adaptToday(action):
            adaptTexts(
                action, session: today?.session ?? L10n.text("today's session"),
                signals: today.map { signalText($0.readiness, format: format) } ?? ""
            )
        case .restWhileIll:
            Texts(L10n.text("You logged being ill. Rest until the symptoms ease, then come back gradually."),
             L10n.text("There is no fixed timeline: how you feel decides when to train again."), nil)
        case let .easeBackIn(daysOff):
            Texts(L10n.format("{1} days since your last session. Keep the plan and ease back in.", daysOff),
             L10n.text(
                "Stop sets a rep or two earlier than usual for a week. Strength lost in a break comes back "
                    + "quickly."
             ), nil)
        case let .fewerSessions(from, perWeek):
            Texts(L10n.format("Plan {1} sessions a week instead of {2}.", perWeek, from),
             L10n.format(
                "You did about {1} a week lately. With the same weekly sets, fewer sessions build about the same "
                    + "muscle and nearly the same strength.", perWeek
             ),
             L10n.format("Plan {1} a week", perWeek))
        case let .extendBlock(weeks):
            Texts(L10n.format("Add {1} weeks to “{2}” to make up for missed sessions.", weeks, blockName),
             L10n.text("The blocks after it move back by the same time."),
             L10n.format("Add {1} weeks", weeks))
        }
    }

    private static func adaptTexts(_ action: DailyRecoveryAction, session: String, signals: String) -> Texts {
        switch action {
        case .skip:
            Texts(L10n.format("Skip {1} today and reassess how you feel.", session), signals, nil)
        case .recoveryDay:
            Texts(L10n.format(
                "Make {1} a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).",
                session
            ), signals, nil)
        case .easier:
            Texts(L10n.format("Keep {1} easy today.", session), signals, nil)
        }
    }
}
