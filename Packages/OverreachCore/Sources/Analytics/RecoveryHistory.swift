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

    public init(lastDay: CalendarDay, kind: Kind) {
        self.lastDay = lastDay
        self.kind = kind
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

    /// The latest recovery that ended before `day`: an accepted deload week, or a detected period that counts
    /// (`needsConfirmation` false). A deload week still in progress is not finished yet and is left out.
    public static func lastRecovery(
        deloads: [DeloadRecord], detected: [DetectedDeload], before day: CalendarDay, calendar: Calendar = .current
    ) -> LastRecovery? {
        let weeks = deloads.map { LastRecovery(lastDay: lastDay(of: $0, calendar: calendar), kind: .deloadWeek) }
        let breaks = detected.filter { !$0.needsConfirmation }.map {
            LastRecovery(lastDay: $0.end, kind: .detectedBreak)
        }
        // On the same last day, an accepted deload week is the clearer answer.
        func rank(_ recovery: LastRecovery) -> (CalendarDay, Int) {
            (recovery.lastDay, recovery.kind == .deloadWeek ? 1 : 0)
        }
        return (weeks + breaks).filter { $0.lastDay < day }.max { rank($0) < rank($1) }
    }
}
