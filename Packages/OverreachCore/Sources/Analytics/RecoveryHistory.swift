import Domain
import Foundation

/// The athlete's last recovery period: the one answer Today, Plan, Workout and the deload advice use for "when did I
/// last deload?" (ADR-0029, ADR-0035).
public struct LastRecovery: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A deload week the athlete accepted.
        case deloadWeek
        /// A break or a much lighter period found in the training history, counted automatically or confirmed.
        case detectedBreak
    }

    /// Its last day.
    public let lastDay: CalendarDay
    public let kind: Kind
    /// Its first day, when known.
    public let firstDay: CalendarDay?

    public init(lastDay: CalendarDay, kind: Kind, firstDay: CalendarDay? = nil) {
        self.lastDay = lastDay
        self.kind = kind
        self.firstDay = firstDay
    }

    /// Days from its first to its last day, inclusive; `nil` when the first day is unknown.
    public func days(calendar: Calendar = .current) -> Int? {
        firstDay.map { PlanReviewer.days(from: $0, to: lastDay, calendar: calendar) + 1 }
    }
}

public enum RecoveryHistory {
    /// The last day of an accepted deload week.
    public static func lastDay(of deload: DeloadRecord, calendar: Calendar = .current) -> CalendarDay {
        deload.start.adding(days: max(1, deload.days) - 1, calendar: calendar)
    }

    /// The accepted deload week that includes `day`, if any.
    public static func deloadInProgress(
        _ profile: AthleteProfile, on day: CalendarDay, calendar: Calendar = .current
    ) -> DeloadRecord? {
        profile.deloads.last { $0.contains(day, calendar: calendar) }
    }

    /// The latest recovery of `discipline` that ended before `day`: an accepted deload week (a strength deload), or a
    /// detected period that counts (`needsConfirmation` false) and rested that discipline. A deload week still in
    /// progress is not finished yet and is left out.
    public static func lastRecovery(
        deloads: [DeloadRecord], detected: [DetectedDeload], before day: CalendarDay,
        for discipline: TrainingDiscipline = .strength, calendar: Calendar = .current
    ) -> LastRecovery? {
        let weeks = discipline == .strength ? deloads.map {
            LastRecovery(lastDay: lastDay(of: $0, calendar: calendar), kind: .deloadWeek, firstDay: $0.start)
        } : []
        let breaks = detected.filter { !$0.needsConfirmation && $0.rests(discipline) }.map {
            LastRecovery(lastDay: $0.end, kind: .detectedBreak, firstDay: $0.start)
        }
        // On the same last day, an accepted deload week is the clearer answer.
        func rank(_ recovery: LastRecovery) -> (CalendarDay, Int) {
            (recovery.lastDay, recovery.kind == .deloadWeek ? 1 : 0)
        }
        return (weeks + breaks).filter { $0.lastDay < day }.max { rank($0) < rank($1) }
    }
}
