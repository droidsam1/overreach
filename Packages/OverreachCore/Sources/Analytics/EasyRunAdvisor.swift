import Domain
import Foundation

/// Suggests an example below normal effort. The dose defaults are `easy-run-example` in the evidence register.
public enum EasyRunAdvisor {
    public static let historyDays = 28
    public static let evidence = EvidenceReference(key: "easy-run-example", level: .heuristic)

    public enum Decision: Hashable, Sendable {
        case plannedRest
        case nearEvent
        case example(minutes: Int, plan: PlannedRun?, isToday: Bool, recentRuns: Int)
    }

    public static func advise(
        goal: RunningGoal, targetDay: CalendarDay?, planned: PlannedRun?, readiness: Readiness,
        metrics: DailyMetrics?, runs: [RunActivity], now: Date, calendar: Calendar = .current
    ) -> Decision? {
        guard goal.distanceMeters > 0, readiness.level == .green || readiness.level == .amber else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let next = planned.flatMap { $0.day >= today ? $0 : nil }
        let scheduledToday = next?.day == today
        if scheduledToday, next?.purpose == .rest { return .plannedRest }
        if let next, next.purpose == .race, next.day <= tomorrow { return .nearEvent }
        if let targetDay, (today...tomorrow).contains(targetDay) { return .nearEvent }
        if scheduledToday, readiness.level == .green, next?.purpose != .easy { return nil }
        guard hasBiometricSupport(readiness, metrics: metrics, today: today, calendar: calendar) else { return nil }

        let start = today.adding(days: -(historyDays - 1), calendar: calendar).startDate(in: calendar)
        // Include a mirrored recording just outside the window before filtering by the preferred record's day.
        let completed = RunDeduplication.removingDuplicates(runs.filter { run in
            run.startedAt <= now && run.durationSeconds.isFinite && run.durationSeconds >= 0
                && run.startedAt.addingTimeInterval(run.durationSeconds) <= now
        }).filter { $0.startedAt >= start }
        // A run with unknown duration still counts as activity when deciding whether to offer another today.
        let dayStart = today.startDate(in: calendar)
        guard !completed.contains(where: { $0.startedAt.addingTimeInterval($0.durationSeconds) >= dayStart })
        else { return nil }
        let recent = completed.filter { $0.durationSeconds > 0 }.suffix(5)
        let fresh = today.adding(days: -14, calendar: calendar).startDate(in: calendar)
        guard let latest = recent.last, latest.startedAt >= fresh else { return nil }
        let durations = recent.map { $0.durationSeconds / 60 }.sorted()
        let typical = durations[(durations.count - 1) / 2]
        let fraction = readiness.level == .amber ? 0.75 : 1.0
        let plannedMinutes = next?.durationMinutes.flatMap { $0 > 0 ? Double($0) : nil }
        let qualityTomorrow = next?.day == tomorrow && [.intervals, .tempo, .long].contains(next?.purpose)
        let ceiling = qualityTomorrow ? 15.0 : (goal.aimsForPainFree ? 20.0 : 30.0)
        let planCeiling = plannedMinutes.map { $0 * (scheduledToday ? fraction : 1) } ?? ceiling
        let minutes = Int(min(ceiling, typical * fraction, planCeiling).rounded(.down))
        guard minutes >= 5 else { return nil }
        return .example(minutes: minutes, plan: next, isToday: scheduledToday, recentRuns: durations.count)
    }

    private static func hasBiometricSupport(
        _ readiness: Readiness, metrics: DailyMetrics?, today: CalendarDay, calendar: Calendar
    ) -> Bool {
        let hasHighSoreness = readiness.reasons.contains { if case .highSoreness = $0 { true } else { false } }
        guard !hasHighSoreness else { return false }
        let latestAcceptable = today.adding(days: -1, calendar: calendar)
        let freshHRV = readiness.hrvCoverage.map { $0.canCompare && $0.latestDay >= latestAcceptable } ?? false
        let sleep = metrics?.sleepSeconds ?? 0
        let hasSleep = metrics?.day == today && sleep.isFinite && sleep > 0
        let pulse = metrics?.restingHeartRate ?? 0
        let hasPulse = metrics?.day == today && pulse.isFinite && pulse > 0
        if readiness.level == .green { return freshHRV || hasSleep }
        return readiness.reasons.contains {
            switch $0 {
            case .hrvBelowBaseline: freshHRV
            case .shortSleep: hasSleep
            case .restingHeartRateElevated: hasPulse
            default: false
            }
        }
    }
}
