import Analytics
import Domain
import Foundation

/// The readiness light for a day, with the inputs every screen and the AI context use (ADR-0035).
public enum ReadinessAssessment {
    /// Days of merged metrics needed before `today`: the readiness baselines (months for phase baselines) plus the
    /// 7 days the deload's recovery signals judge, each against its own full baseline.
    public static func historyDays(tracksCycle: Bool, settings: ReadinessRules.Settings = .init()) -> Int {
        let baseline = tracksCycle ? settings.maximumPhaseBaselineDays : settings.baselineDays
        return max(6, baseline) + RecoveryTrend.windowDays
    }

    public static func historyRange(
        today: CalendarDay, tracksCycle: Bool, settings: ReadinessRules.Settings = .init(),
        calendar: Calendar = .current
    ) -> ClosedRange<CalendarDay> {
        today.adding(days: -historyDays(tracksCycle: tracksCycle, settings: settings), calendar: calendar)...today
    }

    public static func assess(
        today: CalendarDay, history: [DailyMetrics], checkIn: CheckIn?, profile: AthleteProfile?,
        cycle: CycleContext?, settings: ReadinessRules.Settings = .init(), calendar: Calendar = .current
    ) -> Readiness {
        ReadinessRules.readiness(
            today: today, history: history, checkIn: checkIn, settings: settings,
            tracksNaturalCycle: profile?.usesCyclePhase ?? false, cycle: cycle, calendar: calendar
        )
    }
}

/// Everything the deload decision reads, gathered once.
public struct TrainingRecord: Sendable {
    /// Completed sessions of the last year.
    public var sessions: [StrengthSession]
    public var exercises: [Exercise]
    public var settings: [UUID: ProgressionSettings]
    public var routines: [Routine]
    public var runs: [RunActivity]
    public var runReadFailed: Bool
    public var recordings: [RecordedStrengthActivity]
    /// Merged daily metrics covering `ReadinessAssessment.historyRange`.
    public var metrics: [DailyMetrics]
    /// Check-ins of the last 7 days.
    public var checkIns: [CheckIn]
    public var activity: [DailyActivity]
    public var cycle: CycleContext?

    public init(
        sessions: [StrengthSession], exercises: [Exercise], settings: [UUID: ProgressionSettings],
        routines: [Routine] = [], runs: [RunActivity] = [], runReadFailed: Bool = false,
        recordings: [RecordedStrengthActivity] = [], metrics: [DailyMetrics] = [], checkIns: [CheckIn] = [],
        activity: [DailyActivity] = [], cycle: CycleContext? = nil
    ) {
        self.sessions = sessions
        self.exercises = exercises
        self.settings = settings
        self.routines = routines
        self.runs = runs
        self.runReadFailed = runReadFailed
        self.recordings = recordings
        self.metrics = metrics
        self.checkIns = checkIns
        self.activity = activity
        self.cycle = cycle
    }
}

/// The deload decision for a day: a week in progress, a proposal, or a break to confirm first (ADR-0027, ADR-0029,
/// ADR-0035). Screens and the AI context turn it into text; none of them decides it again.
public enum DeloadAssessment: Hashable, Sendable {
    /// An accepted deload week, until `lastDay`.
    case inProgress(lastDay: CalendarDay)
    /// Training and recovery call for a deload week. `walkingIncluded`: the weekly load counts extra walking.
    case proposed(DeloadProposal, walkingIncluded: Bool)
    /// A deload would be proposed, but this unconfirmed break may already have been the rest it calls for.
    case confirmBreak(DetectedDeload)

    /// `nil` when there is nothing to say: no signals, or a proposal postponed until after `today`.
    public static func assess(
        today: CalendarDay, now: Date, profile: AthleteProfile, record: TrainingRecord,
        readinessSettings: ReadinessRules.Settings = .init(), settings: DeloadAdvisor.Settings = .init(),
        calendar: Calendar = .current
    ) -> Self? {
        if let current = RecoveryHistory.deloadInProgress(profile, on: today, calendar: calendar) {
            return .inProgress(lastDay: RecoveryHistory.lastDay(of: current, calendar: calendar))
        }
        if let postponed = profile.deloadPostponedUntil, today <= postponed { return nil }

        let byID = Dictionary(record.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lifts = LiftStatus.assessAll(
            index: ExposureIndex(sessions: record.sessions), exercises: byID, stored: record.settings,
            routines: record.routines, now: now, lookbackDays: settings.lookbackDays
        )
        let recovery = RecoveryTrend.assess(
            today: today, history: record.metrics, checkIns: record.checkIns, settings: readinessSettings,
            cycle: record.cycle, calendar: calendar
        )
        let detected = DeloadDetection.periods(
            sessions: record.sessions, runs: record.runs, profile: profile, routines: record.routines,
            exercises: byID, settings: record.settings, runReadFailed: record.runReadFailed,
            recordings: record.recordings, today: today, calendar: calendar
        )
        let weeklyLoad = weeklyLoad(record: record, profile: profile, today: today, calendar: calendar)
        func lastRecovery(_ periods: [DetectedDeload]) -> LastRecovery? {
            RecoveryHistory.lastRecovery(deloads: profile.deloads, detected: periods, before: today, calendar: calendar)
        }
        func propose(_ periods: [DetectedDeload]) -> DeloadProposal? {
            DeloadAdvisor.proposal(
                lifts: lifts, lastRecovery: lastRecovery(periods), weeklyLoad: weeklyLoad, recovery: recovery,
                now: now, settings: settings, calendar: calendar
            )
        }
        guard let proposal = propose(detected) else { return nil }
        if let pending = unconfirmedBreak(in: detected, after: lastRecovery(detected), today: today),
           propose(detected + [DetectedDeload(start: pending.start, end: pending.end, reason: pending.reason,
                                              needsConfirmation: false)]) == nil {
            // Ask first: if the break was the rest the signals call for, a deload now would repeat it.
            return .confirmBreak(pending)
        }
        return .proposed(proposal, walkingIncluded: (weeklyLoad?.walkingLastWeek ?? 0) > 0)
    }

    private static func weeklyLoad(
        record: TrainingRecord, profile: AthleteProfile, today: CalendarDay, calendar: Calendar
    ) -> WeeklyLoadChange? {
        let range = today.adding(days: Workload.usualStartOffset, calendar: calendar)...today
        let training = record.sessions.filter { range.contains(CalendarDay($0.startedAt, calendar: calendar)) }
        let loads = training.compactMap { Workload.strengthLoad($0, calendar: calendar) }
        // A partly recorded week could look easy simply because its sessions lack effort data.
        guard loads.count == training.count else { return nil }
        let walking = EverydayMovement.walkingLoads(record.activity, in: range, profile: profile, calendar: calendar)
        return Workload.weeklyLoadChange(loads: loads, on: today, calendar: calendar, walking: walking)
    }

    /// The latest unconfirmed period after the last recovery.
    private static func unconfirmedBreak(
        in detected: [DetectedDeload], after lastRecovery: LastRecovery?, today: CalendarDay
    ) -> DetectedDeload? {
        detected.filter { period in
            period.needsConfirmation && period.end < today && lastRecovery.map { period.start > $0.lastDay } ?? true
        }.max { $0.end < $1.end }
    }
}
