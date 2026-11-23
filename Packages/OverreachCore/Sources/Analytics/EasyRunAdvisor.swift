import Domain
import Foundation

/// Suggests an example below normal effort. The dose defaults are `easy-run-example` in the evidence register.
public enum EasyRunAdvisor {
    public static let historyDays = 28
    public static let evidence = EvidenceReference(key: "easy-run-example", level: .heuristic)

    public static let returnEvidence = EvidenceReference(key: "training-breaks", level: .heuristic)

    public struct Settings: Sendable {
        public var amberFraction = 0.75
        public var maximumMinutes = 30
        public var painFreeMaximumMinutes = 20
        public var nearbySessionMaximumMinutes = 15

        public init() {}
    }

    public enum Decision: Hashable, Sendable {
        case plannedRest
        case raceToday
        case nearEvent
        case scheduledStrength
        case familiarEffort
        case multipleToday
        /// Lower-body strength today or a heavy session yesterday, and no run planned for today.
        case lowerBodyRecovery(LowerBodyLoad.Level)
        case returningFromBreak(replacePlanned: Bool)
        case example(minutes: Int, plan: PlannedRun?, isToday: Bool, recentRuns: Int)
    }

    public static func advise(
        goal: RunningGoal?, targetDay: CalendarDay?, schedule: [PlannedRun], readiness: Readiness,
        metrics: DailyMetrics?, runs: [RunActivity], now: Date, calendar: Calendar = .current,
        runningBreak: DetectedDeload? = nil, strength: [PlannedStrength] = [],
        priority: DisciplinePriority = .balanced, allowEffortOnly: Bool = true, lowerBody: LowerBodyLoad.Level = .none,
        rotation: RotationProjection? = nil, settings: Settings = .init()
    ) -> Decision? {
        guard readiness.level == .green || readiness.level == .amber,
              !readiness.reasons.contains(where: \.advisesSkippingTraining) else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let pending = schedule.filter { $0.day >= today && $0.completion == nil && !$0.isPostponed }
        let due = pending.filter { $0.day == today }
        if due.contains(where: { $0.purpose == .race }) { return .raceToday }
        if due.contains(where: { $0.purpose == .rest }) { return .plannedRest }
        if pending.contains(where: { $0.purpose == .race && $0.day <= tomorrow }) { return .nearEvent }
        if let targetDay, (today...tomorrow).contains(targetDay) { return .nearEvent }
        if schedule.contains(where: { $0.day == today && $0.completion != nil }) { return nil }
        if due.count > 1 { return .multipleToday }
        let next = due.first ?? pending.min { $0.day < $1.day }
        let scheduledToday = !due.isEmpty
        let liftingToday = strength.contains { $0.day == today && $0.routineID != nil }
        // A dated plan wins; without one, the projected rotation says whether the legs work tomorrow.
        let datedStrength = strength.contains { $0.day >= today && $0.routineID != nil }
        let liftingTomorrow = datedStrength
            ? strength.contains { $0.day == tomorrow && $0.routineID != nil }
            : rotation?.session(on: tomorrow).map { $0.demand != .none } ?? false
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
        if liftingToday && !scheduledToday && priority != .running { return .scheduledStrength }

        // An unplanned run waits when the legs have just worked, unless the athlete puts running first. A planned run
        // stays, kept short like one next to other sessions.
        let legsWorked = priority != .running && lowerBody != .none
        if legsWorked, !scheduledToday { return .lowerBodyRecovery(lowerBody) }
        let qualityTomorrow = pending.contains {
            $0.day == tomorrow && [.intervals, .tempo, .threshold, .long].contains($0.purpose)
        }
        let protectStrength = priority != .running && (liftingToday || liftingTomorrow)
        let protectNearby = qualityTomorrow || protectStrength || legsWorked
        let returnRuns = DeloadDetection.BreakSettings().runningReturnRuns
        if let resumed, !protectNearby,
           completed.lazy.filter({ $0.startedAt >= resumed }).prefix(returnRuns).count < returnRuns {
            return .returningFromBreak(replacePlanned: scheduledToday && next?.purpose != .easy)
        }
        if scheduledToday, readiness.level == .green, next?.purpose != .easy { return nil }

        let recent = completed.filter { $0.startedAt >= start && $0.durationSeconds > 0 }.suffix(5)
        let fresh = today.adding(days: -14, calendar: calendar).startDate(in: calendar)
        guard let latest = recent.last, latest.startedAt >= fresh else {
            return allowEffortOnly && !scheduledToday && !protectNearby ? .familiarEffort : nil
        }
        let durations = recent.map { $0.durationSeconds / 60 }.sorted()
        let normalCeiling = goal?.aimsForPainFree == true ? settings.painFreeMaximumMinutes : settings.maximumMinutes
        let ceiling = protectNearby ? min(normalCeiling, settings.nearbySessionMaximumMinutes) : normalCeiling
        let typical = durations[(durations.count - 1) / 2]
        guard let minutes = suggestedMinutes(
            typical: typical, plan: next, isToday: scheduledToday, ceiling: ceiling,
            fraction: readiness.level == .amber ? settings.amberFraction : 1
        ) else { return nil }
        return .example(minutes: minutes, plan: next, isToday: scheduledToday, recentRuns: durations.count)
    }

    /// Find a date with an empty running slot and room around the quality session.
    public static func rescheduleDay(for run: PlannedRun, goal: TrainingGoal, calendar: Calendar) -> CalendarDay? {
        (2...7).lazy.map { run.day.adding(days: $0, calendar: calendar) }.first {
            canReschedule(run, to: $0, goal: goal, calendar: calendar)
        }
    }

    public static func canReschedule(
        _ run: PlannedRun, to day: CalendarDay, goal: TrainingGoal, calendar: Calendar
    ) -> Bool {
        let first = run.day.adding(days: 2, calendar: calendar)
        let last = run.day.adding(days: 7, calendar: calendar)
        guard (first...last).contains(day), [.intervals, .tempo, .threshold, .long].contains(run.purpose),
              run.completion == nil, !run.isPostponed else { return false }
        let neighborhood = day.adding(days: -1, calendar: calendar)...day.adding(days: 1, calendar: calendar)
        guard goal.targetDate.map({ !neighborhood.contains($0) }) ?? true else { return false }
        let conflicts = goal.scheduledRuns.contains { other in
            guard other.id != run.id, !other.isPostponed, neighborhood.contains(other.day) else { return false }
            return other.day == day || ![.easy, .rest].contains(other.purpose)
        }
        let strengthConflicts = goal.effectivePriority != .running && goal.scheduledStrength.contains {
            $0.routineID != nil && neighborhood.contains($0.day)
        }
        return !conflicts && !strengthConflicts
    }

    private static func suggestedMinutes(
        typical: Double, plan: PlannedRun?, isToday: Bool, ceiling: Int, fraction: Double
    ) -> Int? {
        let planned = plan?.durationMinutes.flatMap { $0 > 0 ? Double($0) : nil }
        let planCeiling = planned.map { $0 * (isToday ? fraction : 1) } ?? Double(ceiling)
        let duration = min(Double(ceiling), typical * fraction, planCeiling)
        guard duration.isFinite, duration >= 5 else { return nil }
        return Int(exactly: duration.rounded(.down))
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
