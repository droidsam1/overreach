import Domain
import Foundation

/// Training load of one day, in arbitrary but consistent units (e.g. sRPE × minutes).
public struct DailyLoad: Hashable, Sendable {
    public let day: CalendarDay
    public let load: Double

    public init(day: CalendarDay, load: Double) {
        self.day = day
        self.load = load
    }
}

/// Workload calculations shared by strength and running.
public enum Workload {
    /// Session load: RPE (1–10) × duration in minutes (Foster's sRPE method).
    public static func sessionRPELoad(rpe: Double, durationMinutes: Double) -> Double {
        max(0, rpe) * max(0, durationMinutes)
    }

    /// This week's load against the person's usual week (`weekly-load-change` in `docs/evidence.md`).
    ///
    /// - Last week: total load of the 7 days ending on `day` (inclusive).
    /// - Usual week: average weekly load of the 3 weeks before that (days −27…−7). The last week is not part of
    ///   it: the coupled acute:chronic ratio, which includes it, inflates the correlation between the two
    ///   (Lolli et al. 2019).
    ///
    /// Returns `nil` when there is no load in the usual weeks. A high ratio only says this week is well above the
    /// usual one; it is not an injury-risk measure (Impellizzeri et al. 2020, 2021).
    public static func weeklyLoadChange(
        loads: [DailyLoad],
        on day: CalendarDay,
        calendar: Calendar = .current
    ) -> WeeklyLoadChange? {
        let lastWeekStart = day.adding(days: -6, calendar: calendar)
        let usualStart = day.adding(days: -27, calendar: calendar)

        var lastWeek = 0.0
        var usualTotal = 0.0
        for entry in loads where entry.day <= day && entry.day >= usualStart {
            if entry.day >= lastWeekStart {
                lastWeek += entry.load
            } else {
                usualTotal += entry.load
            }
        }

        let usualWeek = usualTotal / 3
        guard usualWeek > 0 else { return nil }
        return WeeklyLoadChange(lastWeek: lastWeek, usualWeek: usualWeek)
    }
}

/// The load of the last 7 days next to the person's usual week (the 3 weeks before it).
public struct WeeklyLoadChange: Hashable, Sendable {
    public let lastWeek: Double
    public let usualWeek: Double

    public init(lastWeek: Double, usualWeek: Double) {
        self.lastWeek = lastWeek
        self.usualWeek = usualWeek
    }

    /// Last week divided by the usual week (1 = as usual).
    public var ratio: Double { usualWeek > 0 ? lastWeek / usualWeek : 0 }
}
