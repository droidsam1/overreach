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

/// The decisions Today presents for a given day.
public struct DailyAssessment: Sendable {
    public let readiness: Readiness
    public let deload: DeloadAssessment?
    public let runningBreak: DetectedDeload?

    public init(
        record: TrainingRecord, profile: AthleteProfile?, checkIn: CheckIn?, now: Date,
        settings: ReadinessRules.Settings = .init(), calendar: Calendar = .current
    ) {
        let today = CalendarDay(now, calendar: calendar)
        readiness = ReadinessAssessment.assess(
            today: today, history: record.metrics, checkIn: checkIn, profile: profile, cycle: record.cycle,
            settings: settings, calendar: calendar
        )
        let periods = profile.map {
            record.recoveryPeriods(profile: $0, today: today, calendar: calendar)
        } ?? []
        runningBreak = profile?.countsBreaksAutomatically == true && !record.runReadFailed && !record.runs.isEmpty
            ? RecoveryHistory.lastLongBreak(in: periods, discipline: .running, before: today, calendar: calendar)
            : nil
        if let profile, !readiness.reasons.contains(where: \.advisesSkippingTraining) {
            deload = DeloadAssessment.assess(
                today: today, now: now, profile: profile, record: record,
                readinessSettings: settings, calendar: calendar, recoveryPeriods: periods
            )
        } else {
            deload = nil
        }
    }
}

/// Everything the deload decision reads, gathered once.
public struct TrainingRecord: Sendable {
    /// Completed sessions, including older history when automatic breaks are enabled.
    public var sessions: [StrengthSession]
    public var exercises: [Exercise]
    public var settings: [UUID: ProgressionSettings]
    public var routines: [Routine]
    public var runs: [RunActivity]
    public var runReadFailed: Bool
    public var recordings: [RecordedStrengthActivity]
    /// Merged daily metrics covering `ReadinessAssessment.historyRange`.
    public var metrics: [DailyMetrics]
    /// Check-ins of the last `RecoveryTrend.stressWindowDays` days.
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

extension TrainingRecord {
    /// Audit the strength log using resolved runs only as context for lower-body suggestions.
    public func muscleBalance(
        profile: AthleteProfile?, resolvedRuns: [RunActivity], now: Date, calendar: Calendar
    ) -> [MuscleBalanceFinding] {
        let start = MuscleBalance.historyWindowStart(now: now, calendar: calendar).startDate(in: calendar)
        let window = start...now
        let metres = resolvedRuns.lazy.filter { window.contains($0.startedAt) }.map(\.distanceMeters)
            .filter { $0.isFinite && $0 > 0 }.reduce(0, +)
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return MuscleBalance.findings(
            history: sessions, exercises: byID, profile: profile ?? AthleteProfile(), now: now,
            runningKilometres: runReadFailed || metres == 0 ? nil : metres / 1_000, calendar: calendar
        )
    }

    /// The same effort-weighted load used in the deload assessment, when comparable weeks are available.
    public func weeklyLoad(
        profile: AthleteProfile, today: CalendarDay, calendar: Calendar
    ) -> WeeklyLoadChange? {
        let range = today.adding(days: Workload.usualStartOffset, calendar: calendar)...today
        let training = sessions.filter { range.contains(CalendarDay($0.startedAt, calendar: calendar)) }
        let loads = training.compactMap { Workload.strengthLoad($0, calendar: calendar) }
        // A partly recorded week could look easy simply because its sessions lack effort data.
        guard loads.count == training.count else { return nil }
        let walking = EverydayMovement.walkingLoads(activity, in: range, profile: profile, calendar: calendar)
        return Workload.weeklyLoadChange(loads: loads, on: today, calendar: calendar, walking: walking)
    }

    fileprivate func recoveryPeriods(
        profile: AthleteProfile, today: CalendarDay, calendar: Calendar
    ) -> [DetectedDeload] {
        DeloadDetection.periods(
            sessions: sessions, runs: runs, profile: profile, routines: routines,
            exercises: Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            settings: settings, runReadFailed: runReadFailed, recordings: recordings, today: today,
            calendar: calendar
        )
    }
}

/// The deload decision for a day: a week in progress, a proposal, or a break to confirm first (ADR-0027, ADR-0029,
/// ADR-0035). Screens and the AI context turn it into text; none of them decides it again.
public enum DeloadAssessment: Hashable, Sendable {
    /// An accepted deload week, until `lastDay`.
    case inProgress(lastDay: CalendarDay, forLifeStress: Bool = false)
    /// Training and recovery call for a deload week. `walkingIncluded`: the weekly load counts extra walking.
    case proposed(DeloadProposal, walkingIncluded: Bool, lastRecovery: LastRecovery?)
    /// A deload would be proposed, but this unconfirmed break may already have been the rest it calls for.
    case confirmBreak(DetectedDeload)

    /// The weekly load ratio when a spike contributed to the proposed deload.
    public var weeklyLoadRatio: Double? {
        guard case let .proposed(proposal, _, _) = self else { return nil }
        for signal in proposal.signals {
            if case let .weeklyLoadSpike(ratio) = signal { return ratio }
        }
        return nil
    }

    /// `nil` when there is nothing to say: no signals, or a proposal postponed until after `today`.
    public static func assess(
        today: CalendarDay, now: Date, profile: AthleteProfile, record: TrainingRecord,
        readinessSettings: ReadinessRules.Settings = .init(), settings: DeloadAdvisor.Settings = .init(),
        calendar: Calendar = .current, recoveryPeriods: [DetectedDeload]? = nil
    ) -> Self? {
        if let current = RecoveryHistory.deloadInProgress(profile, on: today, calendar: calendar) {
            return .inProgress(
                lastDay: RecoveryHistory.lastDay(of: current, calendar: calendar),
                forLifeStress: current.forLifeStress == true
            )
        }
        if let postponed = profile.deloadPostponedUntil, today <= postponed { return nil }

        let detected = recoveryPeriods ?? record.recoveryPeriods(profile: profile, today: today, calendar: calendar)
        let trainingStart = today.adding(days: -TrainingRecordLoader.historyDays, calendar: calendar)
        var start = trainingStart
        if profile.countsBreaksAutomatically, let period = RecoveryHistory.lastLongBreak(
            in: detected, discipline: .strength, before: today, calendar: calendar
        ) {
            guard !RecoveryHistory.isRebuildingStrength(after: period, on: today, calendar: calendar) else {
                return nil
            }
            start = max(trainingStart, period.end.adding(days: 1, calendar: calendar))
        }
        let startDate = start.startDate(in: calendar)
        let sessions = record.sessions.filter { $0.startedAt >= startDate }
        let byID = Dictionary(record.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lifts = LiftStatus.assessAll(
            index: ExposureIndex(sessions: sessions), exercises: byID, stored: record.settings,
            routines: record.routines, now: now, lookbackDays: settings.lookbackDays
        )
        let recovery = RecoveryTrend.assess(
            today: today, history: record.metrics, checkIns: record.checkIns, settings: readinessSettings,
            cycle: record.cycle, calendar: calendar
        )
        let weeklyLoad = record.weeklyLoad(profile: profile, today: today, calendar: calendar)
        let currentExerciseIDs = LiftStatus.currentExerciseIDs(
            sessions: sessions, routines: record.routines, profile: profile, now: now, calendar: calendar
        )
        func lastRecovery(_ periods: [DetectedDeload]) -> LastRecovery? {
            RecoveryHistory.lastRecovery(deloads: profile.deloads, detected: periods, before: today, calendar: calendar)
        }
        func propose(after rest: LastRecovery?) -> DeloadProposal? {
            DeloadAdvisor.proposal(
                lifts: lifts, lastRecovery: rest, weeklyLoad: weeklyLoad, recovery: recovery,
                now: now, settings: settings, calendar: calendar, currentExerciseIDs: currentExerciseIDs
            )
        }
        let last = lastRecovery(detected)
        guard let proposal = propose(after: last) else { return nil }
        let questions = RecoveryHistory.recentQuestions(in: detected, after: last, today: today, calendar: calendar)
        if let pending = questions.first(where: { $0.discipline != .running }),
           propose(after: lastRecovery(detected + [DetectedDeload(
               start: pending.start, end: pending.end, reason: pending.reason, needsConfirmation: false,
               discipline: pending.discipline
           )])) == nil {
            // Ask first: if the break was the rest the signals call for, a deload now would repeat it.
            return .confirmBreak(pending)
        }
        return .proposed(proposal, walkingIncluded: (weeklyLoad?.walkingLastWeek ?? 0) > 0, lastRecovery: last)
    }
}
