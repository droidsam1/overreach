import Domain
import Foundation

/// How recovery went over the last 7 days, for deload decisions (`deload-recovery-signals`). It counts sustained
/// signals, not single bad days: the daily readiness light already handles a single day.
public struct RecoveryTrend: Hashable, Sendable {
    /// Days whose 7-day HRV trend was below the personal range (one HRV statistic, ADR-0024).
    public var hrvTrendLowDays = 0
    /// Days with resting HR at least the configured rise above its 60-day mean.
    public var restingHeartRateHighDays = 0
    /// Nights under the short-sleep threshold.
    public var shortSleepNights = 0
    /// Check-ins with low energy or high soreness.
    public var poorWellbeingCheckIns = 0
    /// A check-in marked sick: return to training gradually instead of deloading (`illness-return`).
    public var sickRecently = false

    public init(
        hrvTrendLowDays: Int = 0, restingHeartRateHighDays: Int = 0, shortSleepNights: Int = 0,
        poorWellbeingCheckIns: Int = 0, sickRecently: Bool = false
    ) {
        self.hrvTrendLowDays = hrvTrendLowDays
        self.restingHeartRateHighDays = restingHeartRateHighDays
        self.shortSleepNights = shortSleepNights
        self.poorWellbeingCheckIns = poorWellbeingCheckIns
        self.sickRecently = sickRecently
    }

    public static let windowDays = 7

    /// - Parameters:
    ///   - history: merged daily metrics covering at least the readiness baseline before the window (60 days).
    ///   - checkIns: check-ins of the window (others are ignored).
    ///   - cycle: menstrual events and tracking mode. Each day is judged with its own phase estimate, so the deload
    ///     signals use phase-aware baselines like the readiness light (`cycle-phase-baselines`).
    public static func assess(
        today: CalendarDay, history: [DailyMetrics], checkIns: [CheckIn],
        settings: ReadinessRules.Settings = ReadinessRules.Settings(), cycle: CycleContext? = nil,
        calendar: Calendar = .current
    ) -> RecoveryTrend {
        let window = (0..<windowDays).map { today.adding(days: -$0, calendar: calendar) }
        var trend = RecoveryTrend()

        // Each day judged as the readiness light judges it (same baselines, one HRV statistic: ADR-0024), without
        // the check-in, which is counted separately below.
        for day in window {
            let reasons = ReadinessRules.readiness(
                today: day, history: history.filter { $0.day <= day }, checkIn: nil, settings: settings,
                cycle: cycle, calendar: calendar
            ).reasons
            // Low HRV that the readiness light reads as the cycle (no phase baseline yet) is not counted either.
            let explainedByCycle = reasons.contains(.hrvMayReflectCycle)
            for reason in reasons {
                switch reason {
                case .hrvBelowBaseline: trend.hrvTrendLowDays += explainedByCycle ? 0 : 1
                case .restingHeartRateElevated: trend.restingHeartRateHighDays += 1
                case .shortSleep: trend.shortSleepNights += 1
                default: break
                }
            }
        }

        let windowSet = Set(window)
        for checkIn in checkIns where windowSet.contains(checkIn.day) {
            if checkIn.isSick { trend.sickRecently = true }
            let lowEnergy = checkIn.energy.map { $0 <= settings.lowEnergy } ?? false
            let sore = checkIn.soreness.map { $0 >= settings.highSoreness } ?? false
            if lowEnergy || sore { trend.poorWellbeingCheckIns += 1 }
        }
        return trend
    }
}
