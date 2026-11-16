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

    /// Acute:chronic workload ratio on `day`, using rolling sums.
    ///
    /// - Acute: total load of the 7 days ending on `day` (inclusive).
    /// - Chronic: average weekly load over the 28 days ending on `day` (total / 4).
    ///
    /// Returns `nil` when there is no chronic load yet. Values above ~1.3–1.5 suggest load is rising too fast.
    public static func acuteChronicRatio(
        loads: [DailyLoad],
        on day: CalendarDay,
        calendar: Calendar = .current
    ) -> Double? {
        let acuteStart = day.adding(days: -6, calendar: calendar)
        let chronicStart = day.adding(days: -27, calendar: calendar)

        var acute = 0.0
        var chronicTotal = 0.0
        for entry in loads where entry.day <= day {
            if entry.day >= chronicStart { chronicTotal += entry.load }
            if entry.day >= acuteStart { acute += entry.load }
        }

        let chronicWeekly = chronicTotal / 4
        guard chronicWeekly > 0 else { return nil }
        return acute / chronicWeekly
    }
}
