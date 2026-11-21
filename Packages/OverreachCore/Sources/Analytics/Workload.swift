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

    /// Logged strength load. When whole-session RPE is absent, the mean working-set RPE is a proxy
    /// only if every working set has a recorded effort.
    public static func strengthLoad(_ session: StrengthSession, calendar: Calendar = .current) -> DailyLoad? {
        guard let seconds = session.durationSeconds, seconds.isFinite, seconds > 0 else { return nil }
        let working = session.entries.flatMap(\.sets).filter(\.isWorking)
        let efforts = session.sessionRPE.map { [$0] } ?? working.compactMap(\.rpe)
        guard session.sessionRPE != nil || efforts.count == working.count, !efforts.isEmpty,
              efforts.allSatisfy({ (1...10).contains($0) }) else { return nil }
        let rpe = efforts.reduce(0, +) / Double(efforts.count)
        return DailyLoad(day: CalendarDay(session.startedAt, calendar: calendar),
                         load: sessionRPELoad(rpe: rpe, durationMinutes: seconds / 60))
    }

    /// Offsets of the two windows used by the comparison.
    public static let usualStartOffset = -27
    private static let lastWeekStartOffset = -6

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
        calendar: Calendar = .current,
        walking: [EverydayMovement.WalkingLoad] = []
    ) -> WeeklyLoadChange? {
        let lastWeekStart = day.adding(days: lastWeekStartOffset, calendar: calendar)
        let usualStart = day.adding(days: usualStartOffset, calendar: calendar)

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
        // Keep a training reference even when walks contribute to both windows.
        let walkingLastWeek = walking.filter { (lastWeekStart...day).contains($0.dailyLoad.day) }
            .reduce(0) { $0 + $1.dailyLoad.load }
        let walkingUsual = walking.filter { $0.dailyLoad.day >= usualStart && $0.dailyLoad.day < lastWeekStart }
            .reduce(0) { $0 + $1.dailyLoad.load } / 3
        return WeeklyLoadChange(lastWeek: lastWeek + walkingLastWeek, usualWeek: usualWeek + walkingUsual,
                                walkingLastWeek: walkingLastWeek)
    }
}

/// The load of the last 7 days next to the person's usual week (the 3 weeks before it).
public struct WeeklyLoadChange: Hashable, Sendable {
    public let lastWeek: Double
    public let usualWeek: Double

    public let walkingLastWeek: Double

    public init(lastWeek: Double, usualWeek: Double, walkingLastWeek: Double = 0) {
        self.lastWeek = lastWeek
        self.usualWeek = usualWeek
        self.walkingLastWeek = walkingLastWeek
    }

    /// Last week divided by the usual week (1 = as usual).
    public var ratio: Double { usualWeek > 0 ? lastWeek / usualWeek : 0 }
}
