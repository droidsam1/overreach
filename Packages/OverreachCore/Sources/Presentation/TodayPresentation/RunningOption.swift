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

    init(goal: RunningGoal, decision: EasyRunAdvisor.Decision, calendar: Calendar, format: Format) {
        self.goal = goal.displayName(format: format)
        switch decision {
        case .plannedRest:
            plan = nil
            advice = L10n.text("Keep your planned running rest day.")
            context = nil
            evidence = nil
            source = nil
        case .nearEvent:
            plan = nil
            advice = L10n.text("Your race or target date is today or tomorrow. Leave the extra run for another day.")
            context = nil
            evidence = nil
            source = nil
        case .example(let minutes, let next, let isToday, let recentRuns):
            if let next {
                let label = next.purpose.displayName
                let minuteLabel = next.durationMinutes.flatMap { $0 > 0 ? " · \($0) min" : nil } ?? ""
                let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
                let date = next.day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
                plan = isToday
                    ? L10n.format("Today's running plan · {1}", label + minuteLabel)
                    : L10n.format("Next planned running day · {1} · {2}", date, label + minuteLabel)
            } else {
                plan = nil
            }
            if isToday, next?.purpose == .easy {
                advice = L10n.format("Keep today's run easy. Try {1} min at a conversational pace.", String(minutes))
            } else if isToday {
                advice = L10n.format("Try {1} min at a conversational pace in place of the planned session.", String(minutes))
            } else {
                advice = L10n.format("If you want to run today, try {1} min at a conversational pace.", String(minutes))
            }
            let anchor = L10n.format("Duration based on {1} recent runs.", String(recentRuns))
            context = goal.aimsForPainFree
                ? anchor + " " + L10n.text("For your pain-free goal, stop if you notice pain.")
                : anchor
            evidence = EasyRunAdvisor.evidence.level.displayName
            source = URL(string: "https://pubmed.ncbi.nlm.nih.gov/18277826/")
        }
    }
}
