import Domain
import Foundation

/// Suggests an example below normal effort. The dose defaults are `easy-run-example` in the evidence register.
public enum EasyRunAdvisor {
    public static let historyDays = 28
    public static let evidence = EvidenceReference(key: "easy-run-example", level: .heuristic)

    public static let returnEvidence = EvidenceReference(key: "training-breaks", level: .heuristic)

    public enum Decision: Hashable, Sendable {
        case plannedRest
        case nearEvent
        case multipleToday
        case returningFromBreak(replacePlanned: Bool)
        case example(minutes: Int, plan: PlannedRun?, isToday: Bool, recentRuns: Int)
    }

    public static func advise(
        goal: RunningGoal?, targetDay: CalendarDay?, schedule: [PlannedRun], readiness: Readiness,
        metrics: DailyMetrics?, runs: [RunActivity], now: Date, calendar: Calendar = .current,
        runningBreak: DetectedDeload? = nil
    ) -> Decision? {
        guard (goal?.distanceMeters ?? 0) > 0 || runningBreak != nil,
              readiness.level == .green || readiness.level == .amber,
              !readiness.reasons.contains(where: \.advisesSkippingTraining) else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let pending = schedule.filter { $0.day >= today && $0.completion == nil && !$0.isPostponed }
        let due = pending.filter { $0.day == today }
        if due.contains(where: { $0.purpose == .rest }) { return .plannedRest }
        if pending.contains(where: { $0.purpose == .race && $0.day <= tomorrow }) { return .nearEvent }
        if let targetDay, (today...tomorrow).contains(targetDay) { return .nearEvent }
        if schedule.contains(where: { $0.day == today && $0.completion != nil }) { return nil }
        if due.count > 1 { return .multipleToday }
        let next = due.first ?? pending.min { $0.day < $1.day }
        let scheduledToday = next?.day == today
        guard hasBiometricSupport(readiness, metrics: metrics, today: today, calendar: calendar) else { return nil }

        let start = today.adding(days: -(historyDays - 1), calendar: calendar).startDate(in: calendar)
        let resumed = runningBreak?.end.adding(days: 1, calendar: calendar).startDate(in: calendar)
        // Include a mirrored recording just outside the window before filtering by the preferred record's day.
        let completed = RunDeduplication.removingDuplicates(runs.filter { run in
            run.startedAt <= now && run.durationSeconds.isFinite && run.durationSeconds >= 0
                && run.startedAt.addingTimeInterval(run.durationSeconds) <= now
        }).filter { $0.startedAt >= min(start, resumed ?? start) }
        // A run with unknown duration still counts as activity when deciding whether to offer another today.
        let dayStart = today.startDate(in: calendar)
        guard !completed.contains(where: { $0.startedAt.addingTimeInterval($0.durationSeconds) >= dayStart })
        else { return nil }
        let returnRuns = DeloadDetection.BreakSettings().runningReturnRuns
        if let resumed, completed.lazy.filter({ $0.startedAt >= resumed }).prefix(returnRuns).count < returnRuns {
            return .returningFromBreak(replacePlanned: scheduledToday && next?.purpose != .easy)
        }
        guard let goal, goal.distanceMeters > 0 else { return nil }
        if scheduledToday, readiness.level == .green, next?.purpose != .easy { return nil }

        let recent = completed.filter { $0.startedAt >= start && $0.durationSeconds > 0 }.suffix(5)
        let fresh = today.adding(days: -14, calendar: calendar).startDate(in: calendar)
        guard let latest = recent.last, latest.startedAt >= fresh else { return nil }
        let durations = recent.map { $0.durationSeconds / 60 }.sorted()
        let typical = durations[(durations.count - 1) / 2]
        let fraction = readiness.level == .amber ? 0.75 : 1.0
        let plannedMinutes = next?.durationMinutes.flatMap { $0 > 0 ? Double($0) : nil }
        let qualityTomorrow = pending.contains {
            $0.day == tomorrow && [.intervals, .tempo, .threshold, .long].contains($0.purpose)
        }
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
