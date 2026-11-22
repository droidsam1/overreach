import Analytics
import Domain
import Foundation
import PresentationKit

public struct RunningOption: Hashable, Sendable {
    public let goal: String
    public let plan: String?
    public let advice: String
    public let context: String?
    public let evidence: String?
    public let source: URL?
    public let explanation: String?
    public let adjustment: PlannedRun?
    public let adjustmentMinutes: Int?
    public let isOptional: Bool

    private init(
        goal: String, advice: String, plan: String? = nil, context: String? = nil, evidence: EvidenceReference? = nil,
        source: String? = nil, explanation: String? = nil, adjustment: PlannedRun? = nil,
        adjustmentMinutes: Int? = nil, isOptional: Bool = false
    ) {
        self.goal = goal
        self.plan = plan
        self.advice = advice
        self.context = context
        self.evidence = evidence?.level.displayName
        self.source = source.flatMap { URL(string: $0) }
        self.explanation = explanation
        self.adjustment = adjustment
        self.adjustmentMinutes = adjustmentMinutes
        self.isOptional = isOptional
    }

    init(
        goal: RunningGoal?, decision: EasyRunAdvisor.Decision, hasRunToday: Bool, calendar: Calendar, format: Format
    ) {
        let title = goal?.displayName(format: format) ?? L10n.text("Running")
        switch decision {
        case .plannedRest:
            self.init(goal: title, advice: L10n.text("Keep your planned running rest day."))
        case .raceToday:
            self.init(goal: title, advice: L10n.text("Your race is today. Follow the recovery advice above."))
        case .scheduledStrength:
            self.init(goal: title, advice: L10n.text("Keep your scheduled strength session as the priority."))
        case .familiarEffort:
            self.init(
                goal: title, advice: L10n.text("If you run today, keep it easy and at a conversational pace."),
                context: Self.painFreeContext(L10n.text("Choose a duration you are used to."), goal: goal),
                isOptional: true
            )
        case .nearEvent:
            self.init(goal: title, advice: L10n.text(
                "Your race or target date is today or tomorrow. Leave the extra run for another day."
            ))
        case .multipleToday:
            self.init(goal: title, advice: L10n.text(
                "You have several runs planned today. Review them in Plan before adding or replacing a run."
            ))
        case .returningFromBreak(let replacePlanned):
            let advice = replacePlanned
                ? L10n.text("Replace today's planned run with an easy run at a conversational pace.")
                : L10n.text("If you run today, keep it easy and at a conversational pace.")
            let text = L10n.text("You're returning from a running break.")
            self.init(
                goal: title, advice: advice, context: Self.painFreeContext(text, goal: goal),
                evidence: EasyRunAdvisor.returnEvidence, source: "https://pubmed.ncbi.nlm.nih.gov/33517866/",
                explanation: L10n.text(
                    "Endurance can change during a break. Keeping the first runs easy is a coaching estimate."
                ), isOptional: !hasRunToday
            )
        case .example(let minutes, let next, let isToday, let recentRuns):
            let plan = next.map { Self.planText($0, isToday: isToday, calendar: calendar, format: format) }
            let reduction = isToday && (next?.purpose != .easy || next?.durationMinutes != minutes)
            let advice: String
            if isToday, !reduction {
                advice = L10n.text("Keep today's planned easy run at a conversational pace.")
            } else if isToday, next?.purpose == .easy {
                advice = L10n.format("Keep today's run easy. Try {1} min at a conversational pace.", String(minutes))
            } else if isToday {
                advice = L10n.format("Try {1} min at a conversational pace in place of the planned session.", String(minutes))
            } else {
                advice = L10n.format("If you want to run today, try {1} min at a conversational pace.", String(minutes))
            }
            let anchor = L10n.format("Duration based on {1} recent runs.", String(recentRuns))
            self.init(
                goal: title, advice: advice, plan: plan, context: Self.painFreeContext(anchor, goal: goal),
                evidence: EasyRunAdvisor.evidence, source: "https://pubmed.ncbi.nlm.nih.gov/18277826/",
                explanation: L10n.text(
                    "A conversational pace keeps the effort easy. The duration is a coaching estimate."
                ), adjustment: reduction && goal != nil ? next : nil, adjustmentMinutes: reduction ? minutes : nil,
                isOptional: !isToday
            )
        }
    }

    private static func planText(_ next: PlannedRun, isToday: Bool, calendar: Calendar, format: Format) -> String {
        let label = next.displayName(format: format)
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let date = next.day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
        return isToday
            ? L10n.format("Today's running plan · {1}", label)
            : L10n.format("Next planned running day · {1} · {2}", date, label)
    }

    private static func painFreeContext(_ text: String, goal: RunningGoal?) -> String {
        goal?.aimsForPainFree == true
            ? text + " " + L10n.text("For your pain-free goal, stop if you notice pain.")
            : text
    }
}
