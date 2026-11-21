import Domain
import Foundation
import PresentationKit

// What the Plan screen leads with (ADR-0014): the next scheduled sessions, a goal summary, and one line about the
// progress that now lives in Recovery & Progress.

extension HybridCalendarRow {
    /// An explicit rest day, as opposed to a day with no entry at all.
    public var isRest: Bool {
        switch self {
        case let .run(row): row.entry.purpose == .rest
        case let .strength(row): row.entry.routineID == nil
        }
    }
}

extension PlanModel {
    /// How many dated sessions the Plan screen lists before pointing to the whole calendar.
    static let nextSessionCount = 3

    /// The next dated sessions and rest days, soonest first.
    public var nextSessionRows: [HybridCalendarRow] {
        Array(upcomingCalendarRows.prefix(Self.nextSessionCount))
    }

    /// There are dated entries beyond `nextSessionRows`.
    public var hasMoreSessions: Bool { upcomingCalendarRows.count > Self.nextSessionCount }

    /// The goal and its target date on one line.
    public var goalSummary: String {
        let name = goalOptions.first { $0.value == goalKind }?.name ?? ""
        guard hasTargetDate else { return name }
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year()
        return L10n.format("{1} · by {2}", name, targetDate.formatted(style))
    }

    /// Something to show in Progress: a recovery period or question, a stalled lift or a linked running result.
    public var hasProgress: Bool {
        hasRecoveryHistory || !liftsToUnblockRows.isEmpty || runningGoalProgress != nil
    }

    /// One line for the Progress row: the last recovery, stalled lifts and the running goal.
    public var progressSummary: String {
        var parts: [String] = []
        if let last = lastDeloadSummary { parts.append(last) }
        switch liftsToUnblockRows.count {
        case 0: break
        case 1: parts.append(L10n.text("1 lift to unblock"))
        case let count: parts.append(L10n.format("{1} lifts to unblock", count))
        }
        if let running = runningGoalProgress { parts.append(running.status) }
        return parts.isEmpty ? L10n.text("No progress to show yet") : parts.joined(separator: " · ")
    }
}
