import Analytics
import Domain
import Foundation
import PresentationKit
import TrainingServices

/// One discipline's training in the last 7 days next to the person's usual week.
public struct RecentLoadRow: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case strength, running, movement, garminEstimate
    }

    public let kind: Kind
    public let title: String
    public let value: String
    /// The usual week, or why there is nothing to compare with.
    public let comparison: String?
    public let details: [String]

    public var id: Kind { kind }
}

/// Recent load by discipline from the shared training record: logged strength, runs once each, everyday movement.
struct RecentLoad {
    let calendar: Calendar
    let format: Format

    func rows(record: TrainingRecord, today: CalendarDay) -> [RecentLoadRow] {
        let weekStart = today.adding(days: -6, calendar: calendar)
        let usualStart = today.adding(days: Workload.usualStartOffset, calendar: calendar)
        func window(_ day: Date) -> Window? {
            let local = CalendarDay(day, calendar: calendar)
            if (weekStart...today).contains(local) { return .last }
            if (usualStart..<weekStart).contains(local) { return .usual }
            return nil
        }
        return [
            strength(record, window), running(record, window),
            movement(record, today: today), garmin(record, today: today),
        ].compactMap { $0 }
    }

    private enum Window { case last, usual }

    private func strength(_ record: TrainingRecord, _ window: (Date) -> Window?) -> RecentLoadRow? {
        var last = (sessions: 0, minutes: 0.0), usual = (sessions: 0, minutes: 0.0)
        for session in record.sessions {
            let minutes = (session.durationSeconds ?? 0) / 60
            switch window(session.startedAt) {
            case .last: last = (last.sessions + 1, last.minutes + minutes)
            case .usual: usual = (usual.sessions + 1, usual.minutes + minutes)
            case nil: break
            }
        }
        guard last.sessions > 0 || usual.sessions > 0 else { return nil }
        let value = last.sessions == 0 ? L10n.text("No sessions") : L10n.format(
            "{1} sessions · {2} min", String(last.sessions), format.number(last.minutes, maxFractionDigits: 0)
        )
        return RecentLoadRow(
            kind: .strength, title: L10n.text("Strength"), value: value,
            comparison: usualText(
                count: Double(usual.sessions) / 3, noun: L10n.text("sessions"), amount: usual.minutes / 3, unit: "min"
            ),
            details: [L10n.text("Logged sessions in the app, last 7 days against the 3 weeks before.")]
        )
    }

    private func running(_ record: TrainingRecord, _ window: (Date) -> Window?) -> RecentLoadRow? {
        guard !record.runReadFailed else { return nil }
        var last = (runs: 0, km: 0.0), usual = (runs: 0, km: 0.0)
        for run in record.runs where run.distanceMeters.isFinite {
            switch window(run.startedAt) {
            case .last: last = (last.runs + 1, last.km + run.distanceMeters / 1_000)
            case .usual: usual = (usual.runs + 1, usual.km + run.distanceMeters / 1_000)
            case nil: break
            }
        }
        guard last.runs > 0 || usual.runs > 0 else { return nil }
        let value = last.runs == 0 ? L10n.text("No runs") : L10n.format(
            "{1} runs · {2} km", String(last.runs), format.number(last.km, maxFractionDigits: 1)
        )
        return RecentLoadRow(
            kind: .running, title: L10n.text("Running"), value: value,
            comparison: usualText(
                count: Double(usual.runs) / 3, noun: L10n.text("runs"), amount: usual.km / 3, unit: "km"
            ),
            details: [L10n.text("Each run counts once, even when several sources recorded it.")]
        )
    }

    private func movement(_ record: TrainingRecord, today: CalendarDay) -> RecentLoadRow? {
        let weekStart = today.adding(days: -6, calendar: calendar)
        let usualStart = today.adding(days: Workload.usualStartOffset, calendar: calendar)
        let last = record.activity.filter { (weekStart...today).contains($0.day) }
        let usual = record.activity.filter { (usualStart..<weekStart).contains($0.day) }
        let lastSteps = last.compactMap(\.steps)
        guard !lastSteps.isEmpty else { return nil }
        let average = Double(lastSteps.reduce(0, +)) / Double(lastSteps.count)
        let usualSteps = usual.compactMap(\.steps)
        let usualAverage = usualSteps.isEmpty ? nil : Double(usualSteps.reduce(0, +)) / Double(usualSteps.count)
        let walks = last.reduce(0) { $0 + $1.walks.count }
        var details = [L10n.format("Average over {1} days with steps", String(lastSteps.count))]
        if walks > 0 { details.append(L10n.format("{1} walks detected", String(walks))) }
        return RecentLoadRow(
            kind: .movement, title: L10n.text("Everyday movement"),
            value: L10n.format("{1} steps a day", format.number(average, maxFractionDigits: 0)),
            comparison: usualAverage.map {
                L10n.format("Usually {1} a day", format.number($0, maxFractionDigits: 0))
            },
            details: details
        )
    }

    /// Garmin's own training load estimate: shown as an estimate, never as an Overreach result.
    private func garmin(_ record: TrainingRecord, today: CalendarDay) -> RecentLoadRow? {
        guard let entry = record.metrics.last(where: { $0.acuteLoad != nil && $0.day <= today }),
              let load = entry.acuteLoad else { return nil }
        var details = [L10n.text("Garmin's estimate. Overreach does not use it in its rules.")]
        if let status = entry.trainingStatus { details.append(L10n.format("Training status: {1}", status)) }
        if let hours = entry.recoveryTimeHours {
            details.append(L10n.format("Recovery time: {1} h", format.number(hours, maxFractionDigits: 0)))
        }
        return RecentLoadRow(
            kind: .garminEstimate, title: L10n.text("Garmin training load"),
            value: L10n.format("Acute load {1}", format.number(load, maxFractionDigits: 0)),
            comparison: nil, details: details
        )
    }

    private func usualText(count: Double, noun: String, amount: Double, unit: String) -> String? {
        guard count > 0 else { return L10n.text("No earlier weeks to compare with") }
        return L10n.format(
            "Usual week: {1} {2} · {3} {4}", format.number(count, maxFractionDigits: 1), noun,
            format.number(amount, maxFractionDigits: 0), unit
        )
    }
}
