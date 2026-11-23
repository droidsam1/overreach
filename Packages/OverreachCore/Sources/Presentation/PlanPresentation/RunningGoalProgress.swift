import Domain
import Foundation
import PresentationKit

public struct RunningGoalResultRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let result: PlannedRunCompletion
    public let date: String
    public let summary: String
    public let painStatus: String
    public let meetsGoal: Bool
}

public struct RunningGoalProgress: Hashable, Sendable {
    public let goal: String
    public let status: String
    public let rows: [RunningGoalResultRow]

    init(goal: RunningGoal, schedule: [PlannedRun], calendar: Calendar, format: Format = Format()) {
        self.goal = goal.displayName(format: format)
        let dateStyle = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated).year()
        rows = schedule.sorted { $0.day > $1.day }.compactMap { entry in
            guard let result = entry.completion else { return nil }
            let distance = result.distanceMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                .map { format.number($0 / 1_000, maxFractionDigits: 3) + " km" }
                ?? L10n.text("Distance unavailable")
            let elapsed = result.durationSeconds
            let time = elapsed.isFinite && elapsed > 0 && elapsed < 7 * 86_400
                ? " · " + format.minutesAndSeconds(Int(elapsed.rounded(.up))) : ""
            let pain: String
            if let worst = result.painReport.worstSeverity, worst > 0 {
                pain = result.settledByMorning == true
                    ? L10n.format("Pain up to {1}/10, settled by morning", worst)
                    : L10n.format("Pain up to {1}/10, not settled by morning", worst)
            } else if result.painDuring == true || result.painAfter == true {
                pain = L10n.text("Pain reported")
            } else if result.painDuring == false && result.painAfter == false {
                pain = L10n.text("Pain-free during and after")
            } else {
                pain = L10n.text("Pain report incomplete")
            }
            return RunningGoalResultRow(id: entry.id, result: result,
                                        date: entry.day.startDate(in: calendar).formatted(dateStyle),
                                        summary: distance + time, painStatus: pain, meetsGoal: goal.isMet(by: result))
        }
        status = rows.contains(where: \.meetsGoal) ? L10n.text("Goal confirmed by a linked run")
            : L10n.text("Goal not yet confirmed by linked runs")
    }
}
