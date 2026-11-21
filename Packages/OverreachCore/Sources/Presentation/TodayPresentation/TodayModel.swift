import Analytics
import Domain
import Foundation
import Observation
import PresentationKit

/// One reason behind the readiness light, with the strength of its evidence.
public struct ReadinessLine: Hashable, Sendable {
    public let text: String
    public let evidence: String
    public let source: URL?
    /// "Learn more" for this reason (ADR-0030); often empty.
    public let readings: [Reading]
}

/// State and actions of the Today screen (ADR-0003, ADR-0014): dependencies come in as `Domain` protocols, the
/// view only reads state and calls actions.
@MainActor
@Observable
public final class TodayModel {
    public private(set) var metrics: DailyMetrics?
    /// The last 7 days (today included), merged across sources, oldest first. Days without data are left out.
    public private(set) var week: [DailyMetrics] = []
    public private(set) var readiness = Readiness(level: .unknown, reasons: [.missingData])
    public private(set) var isLoading = false
    /// Sources that failed during the last load. The screen still shows whatever the others returned.
    public private(set) var failedSources: [DataSourceKind] = []
    /// Why each failed source failed (the system's own message), so the screen can say more than "failed".
    private var failureReasons: [DataSourceKind: String] = [:]
    /// Set when asking a source for access failed, e.g. Apple Health without the HealthKit entitlement.
    public private(set) var accessError: String?
    /// Today's check-in, once filled in.
    public private(set) var checkIn: CheckIn?
    private var recentRunPain = false
    public private(set) var recentTrainingDays: [RecentTrainingDay] = []
    public private(set) var scheduledStrengthToday: ScheduledTrainingRow?
    public private(set) var scheduledRunsToday: [ScheduledTrainingRow] = []
    public private(set) var strengthOption: StrengthOption?
    public private(set) var runningOption: RunningOption?
    private var hasRunningGoal = false
    /// A deload proposal (training reinforced by recovery, `deload-recovery-signals`) or the deload week in progress.
    public private(set) var deloadAdvice: DeloadAdvice?
    /// The next session with the deload applied, when the app knows which session comes next.
    public private(set) var deloadSession: DeloadSessionPreview?
    /// Workouts the athlete can say they will do next, when there is no plan (most recent first, or rotation order).
    public private(set) var strengthChoices: [StrengthChoice] = []
    /// What the app knows about the next session: the detected rotation, or that it cannot tell.
    public private(set) var strengthChoiceNote: String?
    private var recentWorkouts: WorkoutContext?
    private var strengthInputs: StrengthInputs?
    private var chosenWorkout: (day: CalendarDay, id: String)?
    private var trainingReadFailed = false
    private var activeLoad: UUID?
    private var loadedDay: CalendarDay?
    /// Whether a Garmin account is connected (ADR-0022).
    public private(set) var isGarminConnected = false
    /// The person said they use a Garmin (first-run setup).
    private var wearsGarmin = false

    private let sources: [any MetricsSource]
    private let garmin: (any GarminAccount)?
    private let profiles: (any ProfileRepository)?
    private let cycleSource: (any CycleSource)?
    /// Menstrual events and tracking mode of the last load, for phase-aware baselines (`cycle-phase-baselines`).
    private var cycleContext: CycleContext?
    private let checkIns: (any CheckInRepository)?
    private let backup: (any BackupService)?
    private let workouts: (any WorkoutRepository)?
    private let exercises: (any ExerciseRepository)?
    private let recordedStrength: (any RecordedStrengthSource)?
    private let routines: (any RoutineRepository)?
    private let progression: (any ProgressionSettingsRepository)?
    private let readinessSettings: ReadinessRules.Settings
    private let calendar: Calendar
    private let format: Format

    // MARK: Screen state

    public var readinessLevel: ReadinessLevel { readiness.level }
    public var readinessTitle: String { readiness.level.displayName }

    /// What the light means for today's training.
    public var readinessAdvice: String {
        if readiness.reasons.contains(where: \.advisesSkippingTraining) {
            return safetyAdvice
        }
        return switch readiness.level {
        case .green: L10n.text("Train as planned.")
        case .amber: hasRunningGoal || scheduledStrengthToday != nil ? L10n.text("Keep it easy today.")
            : L10n.text("Keep it easy today. Run at a pace you can talk at, or lift with light effort.")
        case .red: L10n.text("Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        case .unknown: L10n.text("Not enough data yet to judge today.")
        }
    }

    private var safetyAdvice: String {
        if readiness.reasons.contains(.exerciseWarningSigns) {
            return L10n.text("Skip training and seek medical advice before returning to exercise.")
        }
        if readiness.reasons.contains(.runningPainLimitsTraining) {
            return L10n.text("Skip today's session and reassess the pain before running again.")
        }
        if readiness.reasons.contains(.markedSick) {
            return L10n.text("Rest today. Ease back into training once you feel well again.")
        }
        return L10n.text("Skip training today and reassess how you feel.")
    }

    /// Why the light has its colour, each reason with its evidence level.
    public var readinessLines: [ReadinessLine] {
        readiness.reasons.map { reason in
            let evidence = ReadinessRules.evidence(for: reason)
            let source = ReadinessRules.evidenceURL(for: reason)
            return ReadinessLine(
                text: text(for: reason), evidence: evidence.level.displayName, source: source,
                // The research source already has its own link.
                readings: FurtherReading.readings(for: evidence).filter { $0.url != source }
            )
        }
    }

    public var hrvCoverageNote: String? {
        guard let coverage = readiness.hrvCoverage else { return hrvSkippedNote }
        guard !coverage.canCompare else { return nil }
        let series = coverage.metric?.seriesLabel ?? L10n.text("HRV")
        if coverage.baselineReadings < coverage.minimumBaselineReadings {
            return L10n.format(
                "Still building your usual HRV range ({1}: {2} of {3} comparable readings needed).",
                series, String(coverage.baselineReadings), String(coverage.minimumBaselineReadings)
            )
        }
        return L10n.format(
            "Too few comparable HRV readings ({1}) in the last {2} days ({3} available, {4} needed).",
            series, String(coverage.recentDays), String(coverage.recentReadings), String(coverage.minimumRecentReadings)
        )
    }

    /// Why no HRV series was judged when none had a usable reading in the recent window (ADR-0032).
    private var hrvSkippedNote: String? {
        guard let input = readiness.hrvInput, case .hrv(let series?) = input.input else { return nil }
        switch input.status {
        case .stale:
            guard let latest = input.latestDay else { return nil }
            let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
            return L10n.format(
                "HRV not used today: no recent reading ({1}). The latest was on {2}.",
                series.metric.seriesLabel, latest.startDate(in: calendar).formatted(style.day().month(.abbreviated))
            )
        case .outOfRange:
            return L10n.format(
                "HRV not used today: the recent readings ({1}) are outside the plausible range.",
                series.metric.seriesLabel
            )
        default:
            return nil
        }
    }

    public var showsReadinessDetails: Bool { !readiness.reasons.isEmpty || hrvCoverageNote != nil }
    public var showsReadinessCard: Bool { loadedDay != nil && (readinessLevel != .unknown || hrvCoverageNote != nil) }

    public var readinessSummary: String? {
        if let summary = explanation.summary { return summary }
        return readiness.reasons.first.flatMap { $0 == .missingData ? nil : text(for: $0) }
    }
    public var readinessContext: [String] { explanation.context }
    public var readinessTrainingContext: ReadinessTrainingContext? { isLoading ? nil : explanation.trainingContext }

    private var explanation: ReadinessExplanation {
        ReadinessExplanation(readiness: readiness, today: metrics, week: week, training: recentTrainingDays,
                             calendar: calendar, format: format)
    }

    /// Recent workouts feed the readiness explanation, the deload and the strength option; History lists them.
    public var trainingReadNote: String? {
        trainingReadFailed ? L10n.text("Some recent workouts could not be loaded.") : nil
    }

    /// The check-in button only shows when check-ins can be stored.
    public var showsCheckIn: Bool { checkIns != nil }
    public var checkInButtonTitle: String {
        if let title = CheckInModel.title(for: suggestedContextQuestion) { return title }
        return checkIn == nil ? L10n.text("How do you feel today?") : L10n.text("Edit today's check-in")
    }

    private var suggestedContextQuestion: CheckIn.Context.Question? {
        guard !isLoading, checkIn?.context == nil, let loadedDay else { return nil }
        let yesterday = loadedDay.adding(days: -1, calendar: calendar)
        let trainedRecently = recentTrainingDays.contains { $0.id >= yesterday && !$0.workouts.isEmpty }
        return ReadinessRules.contextQuestion(
            for: readiness, recentRunPain: recentRunPain, trainedRecently: trainedRecently
        )
    }

    /// "Energy 4/5 · Soreness 1/3", or "Sick" — what today's check-in said.
    public var checkInSummary: String? {
        guard let checkIn else { return nil }
        if checkIn.exerciseWarningSigns == true { return L10n.text("Symptoms to discuss with a clinician") }
        if checkIn.isSick { return L10n.text("Sick") }
        var parts: [String] = []
        if let energy = checkIn.energy { parts.append(L10n.format("Energy {1}/5", String(energy))) }
        if let soreness = checkIn.soreness { parts.append(L10n.format("Soreness {1}/3", String(soreness))) }
        switch checkIn.context?.answer == .yes ? checkIn.context?.question : nil {
        case .symptoms: parts.append(L10n.text("New symptoms affect training"))
        case .stress: parts.append(L10n.text("More stress than usual"))
        case .fatigue: parts.append(L10n.text("More fatigue than usual"))
        case .runningPain: parts.append(L10n.text("Running pain worsened or affected your stride"))
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The check-in sheet for today. After it saves, call `load()` to update the light.
    public func makeCheckInModel(now: Date = .now) -> CheckInModel? {
        guard let checkIns else { return nil }
        let today = CalendarDay(now, calendar: calendar)
        return CheckInModel(
            day: today, existing: checkIn?.day == today ? checkIn : nil, checkIns: checkIns, backup: backup,
            contextQuestion: loadedDay == today ? suggestedContextQuestion : nil
        )
    }

    public var hrvMs: Double? { metrics?.hrvNightlyAverageMs }
    public var restingHeartRate: Double? { metrics?.restingHeartRate }
    /// Sleep in hours (stored in seconds).
    public var sleepHours: Double? { metrics?.sleepSeconds.map { $0 / 3_600 } }
    public var bodyBattery: Double? { metrics?.bodyBatteryHigh }
    public var steps: Double? { metrics?.steps.map(Double.init) }
    public var vo2Max: Double? { metrics?.vo2Max }
    public var stress: Double? { metrics?.averageStress }

    // A tile shows only when some connected source measures that metric: a value today or in the last 7 days. Without
    // an Apple Watch or Garmin there is no HRV tile at all, rather than an empty one.
    public var showsSleep: Bool { has(\.sleepSeconds) }
    public var showsHRV: Bool { has(\.hrvNightlyAverageMs) }
    public var showsRestingHeartRate: Bool { has(\.restingHeartRate) }
    public var showsSteps: Bool { has { $0.steps.map(Double.init) } }
    /// Body Battery and stress are Garmin's.
    public var showsBodyBattery: Bool { has(\.bodyBatteryHigh) }
    public var showsStress: Bool { has(\.averageStress) }
    public var showsVO2Max: Bool { has(\.vo2Max) }
    /// Whether any metric tile shows.
    public var showsMetrics: Bool {
        showsSleep || showsHRV || showsRestingHeartRate || showsSteps || showsBodyBattery || showsStress
            || showsVO2Max
    }

    /// The "Connect Garmin" card: for someone who said they use a Garmin and has not connected it, or when no source
    /// has given anything yet. Settings → Garmin is always there too.
    public var showsConnectGarmin: Bool {
        garmin != nil && !isGarminConnected && !isLoading && (wearsGarmin || !showsMetrics)
    }

    // Every number says what kind it is (evidence review 2026-11, §5): measured by the devices, estimated by them, or
    // computed by Overreach. Sleep stages, Garmin's scores and VO2max are the watch's estimates and never feed a rule.

    /// "Deep 1.2 h · REM 1.6 h (watch estimate)": consumer sleep staging agrees only fairly to moderately with a
    /// sleep lab (`wearable-sleep-stages`).
    public var sleepCaption: String? {
        guard let metrics, metrics.deepSleepSeconds != nil || metrics.remSleepSeconds != nil else { return nil }
        let hours = { (seconds: Double?) in self.format.number((seconds ?? 0) / 3_600, maxFractionDigits: 1) }
        return L10n.format(
            "Deep {1} h · REM {2} h (watch estimate)", hours(metrics.deepSleepSeconds), hours(metrics.remSleepSeconds)
        )
    }

    /// "RMSSD · 7-day avg 42 ms": the statistic shown for the latest night, and its weekly average. RMSSD and SDNN are
    /// separate series and never averaged together (ADR-0025).
    public var hrvCaption: String? {
        let latest = ([metrics].compactMap { $0 } + week.reversed()).lazy.compactMap(\.hrvMetric).first
        guard let latest else { return nil }
        let statistic = latest.rawValue.uppercased()
        guard let weekly = average({ $0.hrv(latest) }) else { return statistic }
        return statistic + " · " + self.weekly(format.number(weekly, maxFractionDigits: 0) + " ms")
    }

    /// Body Battery and stress are Garmin's own scores, not validated independently (`composite-scores`).
    public var bodyBatteryCaption: String { L10n.text("Garmin's estimate") }
    public var stressCaption: String { L10n.text("Garmin's estimate") }
    /// Watch VO2max estimates have a wide individual error: useful as a long-term trend (`wearable-vo2max`).
    public var vo2MaxCaption: String { L10n.text("Watch estimate, follow the trend") }
    public var restingHeartRateCaption: String? {
        average(\.restingHeartRate).map { weekly(format.number($0, maxFractionDigits: 0) + " bpm") }
    }
    public var sleepAverageCaption: String? {
        average(\.sleepSeconds).map { weekly(format.number($0 / 3_600, maxFractionDigits: 1) + " h") }
    }
    public var stepsCaption: String? {
        average { $0.steps.map(Double.init) }.map { weekly(format.number($0, maxFractionDigits: 0)) }
    }

    /// "From Apple Health · Garmin" — where today's numbers come from.
    public var sourcesText: String? {
        guard let metrics, !metrics.sources.isEmpty else { return nil }
        let names = DataSourceKind.allCases.filter(metrics.sources.contains).map(\.displayName)
        return L10n.format("From {1}", names.joined(separator: " · "))
    }

    public var showsLoadingIndicator: Bool { isLoading && metrics == nil }
    public var showsSourceWarning: Bool { !failedSources.isEmpty }
    /// "Apple Health: <system message>" for each failed source, one per line.
    public var sourceWarningDetail: String? {
        let lines = failedSources.compactMap { kind in failureReasons[kind].map { "\(kind.displayName): \($0)" } }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
    public var showsNoDataHint: Bool { !isLoading && metrics == nil && failedSources.isEmpty }
    /// The "Connect Apple Health" button: shown while there is nothing to display.
    public var showsConnectHealth: Bool { !isLoading && metrics == nil }

    /// - Parameter sources: metric sources in priority order. When two sources report the same value,
    ///   the first one wins (e.g. `[garmin, appleHealth]`).
    /// - Parameter checkIns: today's check-in adds how the user feels (and "sick") to the readiness light.
    /// - Parameter cycle: menstrual flow from Apple Health, read only for a natural cycle (ADR-0009).
    public init(
        sources: [any MetricsSource], checkIns: (any CheckInRepository)? = nil, backup: (any BackupService)? = nil,
        garmin: (any GarminAccount)? = nil, profiles: (any ProfileRepository)? = nil,
        workouts: (any WorkoutRepository)? = nil, exercises: (any ExerciseRepository)? = nil,
        recordedStrength: (any RecordedStrengthSource)? = nil, routines: (any RoutineRepository)? = nil,
        progression: (any ProgressionSettingsRepository)? = nil, cycle: (any CycleSource)? = nil,
        readinessSettings: ReadinessRules.Settings = ReadinessRules.Settings(), calendar: Calendar = .current,
        format: Format = Format()
    ) {
        self.sources = sources
        self.cycleSource = cycle
        self.garmin = garmin
        self.profiles = profiles
        self.checkIns = checkIns
        self.backup = backup
        self.workouts = workouts
        self.exercises = exercises
        self.recordedStrength = recordedStrength
        self.routines = routines
        self.progression = progression
        self.readinessSettings = readinessSettings
        self.calendar = calendar
        self.format = format
    }

    public func load(now: Date = .now) async {
        let loadID = UUID()
        activeLoad = loadID
        isLoading = true
        scheduledStrengthToday = nil
        scheduledRunsToday = []
        strengthOption = nil
        strengthInputs = nil
        runningOption = nil
        recentRunPain = false
        defer {
            if activeLoad == loadID {
                isLoading = false
                activeLoad = nil
            }
        }

        let today = CalendarDay(now, calendar: calendar)
        let profile = try? await profiles?.profile()
        let cycle = await readCycle(profile: profile, today: today)
        // The readiness baselines need weeks of history (months for phase baselines, plus the 7 days the deload
        // signals judge); the screen shows the last 7 days.
        let historyDays = cycle == nil
            ? max(6, readinessSettings.baselineDays)
            : max(6, readinessSettings.maximumPhaseBaselineDays) + RecoveryTrend.windowDays
        let range = today.adding(days: -historyDays, calendar: calendar)...today
        let weekStart = today.adding(days: -6, calendar: calendar)
        var byDay: [CalendarDay: DailyMetrics] = [:]
        var failures: [DataSourceKind] = []
        var reasons: [DataSourceKind: String] = [:]
        var availableSources: [any MetricsSource] = []

        for source in sources {
            guard await source.isAvailable() else { continue }
            availableSources.append(source)
            do {
                for day in try await source.dailyMetrics(in: range) where range.contains(day.day) {
                    byDay[day.day] = (byDay[day.day] ?? DailyMetrics(day: day.day)).merging(day)
                }
            } catch {
                failures.append(source.kind)
                reasons[source.kind] = error.localizedDescription
            }
        }

        let checkIn = (try? await checkIns?.checkIn(for: today)).flatMap { $0.day == today ? $0 : nil }
        let garminConnected = await garmin?.connection() != nil
        guard activeLoad == loadID else { return }
        cycleContext = cycle
        let goal = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        hasRunningGoal = goal?.running.map { $0.distanceMeters > 0 } ?? false
        loadedDay = today
        let history = byDay.values.filter { !$0.sources.isEmpty }.sorted { $0.day < $1.day }
        week = history.filter { $0.day >= weekStart }
        metrics = byDay[today].flatMap { $0.sources.isEmpty ? nil : $0 }
        failedSources = failures
        failureReasons = reasons
        self.checkIn = checkIn
        isGarminConnected = garminConnected
        wearsGarmin = profile?.wearables.contains(.garmin) ?? false
        readiness = ReadinessRules.readiness(
            today: today, history: history, checkIn: checkIn, settings: readinessSettings,
            tracksNaturalCycle: profile?.usesCyclePhase ?? false, cycle: cycle, calendar: calendar
        )
        await loadRecentTraining(in: weekStart...today, now: now, sources: availableSources, profile: profile,
                                 loadID: loadID, metricsHistory: history)
    }

    private func loadRecentTraining(
        in range: ClosedRange<CalendarDay>, now: Date, sources: [any MetricsSource], profile: AthleteProfile?,
        loadID: UUID, metricsHistory: [DailyMetrics]
    ) async {
        // Include the previous day so copies across midnight can match before filtering to the visible week.
        let start = range.lowerBound.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let deloadStart = range.upperBound.adding(days: -DeloadDetection.historyDays, calendar: calendar)
            .startDate(in: calendar)
        let readsDeloadHistory = profile != nil && workouts != nil
        let runningStart = hasRunningGoal && (readiness.level == .amber || readiness.level == .green)
            ? range.upperBound.adding(days: -EasyRunAdvisor.historyDays, calendar: calendar).startDate(in: calendar)
            : start
        async let logged = try? workouts?.sessions(from: start, to: now)
        async let catalog = try? exercises?.allExercises()
        async let watch = recordedStrength?.strengthActivities(from: readsDeloadHistory ? deloadStart : start, to: now)
        async let checkInHistory = try? checkIns?.checkIns(in: range)
        async let runs = Self.readRecentRuns(sources: sources, from: readsDeloadHistory ? min(deloadStart, runningStart) : runningStart, to: now)
        let (sessions, allExercises, recordings, previousCheckIns, runResult) = await (
            logged, catalog, watch, checkInHistory, runs
        )
        guard activeLoad == loadID else { return }
        trainingReadFailed = runResult.failed || (workouts != nil && sessions == nil)
        let currentCheckIn = checkIn.map { [$0] } ?? []
        let recentRecordings = (recordings ?? []).filter { $0.endedAt >= start }
        recentTrainingDays = RecentTraining(calendar: calendar, format: format).days(
            in: range, through: now, metrics: week, checkIns: currentCheckIn + (previousCheckIns ?? []),
            runs: runResult.activities, sessions: sessions ?? [], recordings: recentRecordings, exercises: allExercises ?? []
        )
        let today = range.upperBound
        let goal = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }
        loadRunningPlan(goal: goal, today: today, now: now, runs: runResult.failed ? [] : runResult.activities)
        await loadWorkoutContext(today: today, now: now, profile: profile, catalog: allExercises ?? [], loadID: loadID)
        guard activeLoad == loadID else { return }
        await loadDeloadAdvice(
            now: now, history: metricsHistory, profile: profile,
            training: DeloadTraining(
                runs: runResult.activities, runReadFailed: runResult.failed,
                recordings: recordings ?? [], catalog: allExercises ?? []
            ),
            loadID: loadID
        )
        guard activeLoad == loadID else { return }
        updateDeloadSession()
        let assignment = goal?.scheduledStrength.first { $0.day == today }
        var assignedRoutine: Routine?
        if let assignment {
            if let routineID = assignment.routineID {
                assignedRoutine = (try? await routines?.allRoutines())?.first { $0.id == routineID }
            }
            guard activeLoad == loadID else { return }
            scheduledStrengthToday = ScheduledTrainingRow.strength(
                assignment, routine: assignedRoutine, sessions: sessions ?? [], now: now, calendar: calendar
            )
            // A rest day or a missing assigned routine suppresses the undated fallback.
            guard assignedRoutine != nil else { return }
        }
        guard readiness.level == .amber, let sessions,
              !hasStrengthToday(sessions: sessions, recordings: recentRecordings, now: now) else { return }
        await loadStrengthOption(today: today, now: now, profile: profile, assignedRoutine: assignedRoutine,
                                 catalog: allExercises ?? [], loadID: loadID)
    }

    private func loadRunningPlan(goal: TrainingGoal?, today: CalendarDay, now: Date, runs: [RunActivity]) {
        guard let goal, let running = goal.running else { return }
        let schedule = goal.scheduledRuns
        let yesterday = today.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let latestRun = schedule.compactMap(\.completion).filter {
            $0.durationSeconds.isFinite && $0.durationSeconds > 0
                && (yesterday...now).contains($0.startedAt.addingTimeInterval($0.durationSeconds))
        }.max { $0.startedAt < $1.startedAt }
        recentRunPain = latestRun?.painDuring == true || latestRun?.painAfter == true
        scheduledRunsToday = schedule.filter { $0.day == today }.map { ScheduledTrainingRow.run($0, format: format) }
        if let decision = EasyRunAdvisor.advise(
            goal: running, targetDay: goal.targetDate, schedule: schedule, readiness: readiness, metrics: metrics,
            runs: runs, now: now, calendar: calendar
        ), decision != .plannedRest {
            runningOption = RunningOption(goal: running, decision: decision, calendar: calendar, format: format)
        }
    }

    // MARK: Deload

    /// Accepts the proposed deload: a deload week from today. It also resets "weeks since the last deload".
    public func acceptDeload(now: Date = .now) async {
        guard let profiles, var profile = try? await profiles.profile() else { return }
        let today = CalendarDay(now, calendar: calendar)
        profile.deloads.append(DeloadRecord(start: today, days: DeloadAdvisor.Settings().plan.durationDays))
        profile.deloadPostponedUntil = nil
        try? await profiles.save(profile)
        await load(now: now)
    }

    /// Hides the proposal for a week. It comes back then if training and recovery still suggest it.
    public func postponeDeload(now: Date = .now) async {
        guard let profiles, var profile = try? await profiles.profile() else { return }
        profile.deloadPostponedUntil = CalendarDay(now, calendar: calendar).adding(days: 6, calendar: calendar)
        try? await profiles.save(profile)
        deloadAdvice = nil
    }

    /// Answers whether a detected break counted as a deload, as Plan does (ADR-0029). A yes resets the deload
    /// interval; a no lets the proposal through.
    public func reviewBreak(accepted: Bool, now: Date = .now) async {
        guard let profiles, case let .confirmBreak(period) = deloadAdvice?.state,
              var profile = try? await profiles.profile() else { return }
        profile.deloadDecisions.removeAll { $0.start == period.start }
        profile.deloadDecisions.append(
            DeloadDecision(start: period.start, end: period.end, reason: period.reason, accepted: accepted)
        )
        try? await profiles.save(profile)
        await load(now: now)
    }

    private struct DeloadTraining {
        let runs: [RunActivity]
        let runReadFailed: Bool
        let recordings: [RecordedStrengthActivity]
        let catalog: [Exercise]
    }

    private func loadDeloadAdvice(
        now: Date, history: [DailyMetrics], profile: AthleteProfile?, training: DeloadTraining, loadID: UUID
    ) async {
        guard !readiness.reasons.contains(where: \.advisesSkippingTraining), let profile, let workouts else {
            deloadAdvice = nil
            return
        }
        let today = CalendarDay(now, calendar: calendar)
        let weekStart = today.adding(days: -(RecoveryTrend.windowDays - 1), calendar: calendar)
        let start = today.adding(days: -DeloadDetection.historyDays, calendar: calendar).startDate(in: calendar)
        async let logged = try? workouts.sessions(from: start, to: now)
        async let allRoutines = try? routines?.allRoutines()
        async let allSettings = try? progression?.allProgressionSettings()
        async let weekCheckIns = try? checkIns?.checkIns(in: weekStart...today)
        let (sessions, routines, settings, recentCheckIns) = await (logged, allRoutines, allSettings, weekCheckIns)
        guard activeLoad == loadID else { return }
        let completed = (sessions ?? []).filter { RecentTraining.isCompleted($0, through: now) }
        let calendar = calendar
        let format = format
        let readinessSettings = readinessSettings
        let cycle = cycleContext
        let advice = await Task.detached(priority: .userInitiated) {
            DeloadAdvice.make(
                today: today, now: now, sessions: completed, exercises: training.catalog, settings: settings ?? [:],
                profile: profile, history: history, checkIns: recentCheckIns ?? [],
                runs: training.runs, runReadFailed: training.runReadFailed, routines: routines ?? [],
                recordings: training.recordings, cycle: cycle,
                readinessSettings: readinessSettings, calendar: calendar, format: format
            )
        }.value
        guard activeLoad == loadID else { return }
        deloadAdvice = advice
    }

    /// Menstrual events of the last year (enough for 6 cycles and the estimates of past days), only for a natural
    /// cycle. A failed read leaves the overall baselines in place.
    private func readCycle(profile: AthleteProfile?, today: CalendarDay) async -> CycleContext? {
        guard let profile, profile.usesCyclePhase, let cycleSource else { return nil }
        let range = today.adding(days: -Self.cycleHistoryDays, calendar: calendar)...today
        let events = (try? await cycleSource.menstrualEvents(in: range)) ?? []
        return CycleContext(mode: profile.cycleTracking, events: events)
    }

    static let cycleHistoryDays = 365

    private func hasStrengthToday(sessions: [StrengthSession], recordings: [RecordedStrengthActivity], now: Date) -> Bool {
        let start = calendar.startOfDay(for: now)
        return sessions.contains { $0.startedAt <= now && ($0.endedAt ?? $0.startedAt) >= start }
            || recordings.contains { $0.durationSeconds.isFinite && (start...now).contains($0.endedAt) }
    }

    private func loadStrengthOption(
        today: CalendarDay, now: Date, profile: AthleteProfile?, assignedRoutine: Routine?, catalog: [Exercise],
        loadID: UUID
    ) async {
        let blocks = assignedRoutine == nil ? profile?.declaredBlocks ?? [] : []
        let historyStart = now.addingTimeInterval(-ProgressionTargets.historyWindow)
        let blockStart = PlanSchedule.runningBlock(blocks, today: today, calendar: calendar)?.start.startDate(in: calendar)
        async let history = try? workouts?.sessions(from: min(historyStart, blockStart ?? historyStart), to: now)
        async let allRoutines = assignedRoutine == nil ? try? routines?.allRoutines() : nil
        async let allSettings = try? progression?.allProgressionSettings()
        let (sessions, availableRoutines, settings) = await (history, allRoutines, allSettings)
        guard activeLoad == loadID, let sessions, !hasStrengthToday(sessions: sessions, recordings: [], now: now)
        else { return }
        let completed = sessions.filter { RecentTraining.isCompleted($0, through: now) }
        let planned = PlanSchedule.next(blocks: blocks, routines: availableRoutines ?? [], sessions: completed,
                                        today: today, calendar: calendar)
        let familiarityStart = today.adding(days: -EasyStrengthAdjustment.familiarityDays, calendar: calendar)
            .startDate(in: calendar)
        let settingsUnavailable = progression != nil && settings == nil
        strengthInputs = StrengthInputs(
            assignedRoutine: assignedRoutine, plannedRoutine: settingsUnavailable ? nil : planned?.routine,
            sessions: completed, catalog: assignedRoutine != nil && settingsUnavailable ? [] : catalog,
            settings: settings ?? [:], historyStart: historyStart, familiarityStart: familiarityStart
        )
        rebuildStrengthOption()
    }

    // MARK: Next strength session

    /// Says which workout the athlete will do next, when the app could not tell or guessed wrong. It lasts for today.
    public func chooseStrengthSession(_ id: String) {
        guard let day = loadedDay, strengthChoices.contains(where: { $0.id == id }) else { return }
        chosenWorkout = (day, id)
        updateStrengthChoices()
        rebuildStrengthOption()
        updateDeloadSession()
    }

    /// Completed sessions in this window are enough to see a rotation of up to six workouts done once or twice a week.
    static let rotationHistoryDays = 120

    private struct WorkoutContext {
        let sessions: [StrengthSession]
        let catalog: [Exercise]
        let settings: [UUID: ProgressionSettings]
        let rotation: SessionRotation?
        /// The routine a declared plan or today's assignment has next. It wins over a detected rotation.
        let planned: SessionRotation.Slot?
        let recent: [SessionRotation.Slot]
    }

    private struct StrengthInputs {
        let assignedRoutine: Routine?
        let plannedRoutine: Routine?
        let sessions: [StrengthSession]
        let catalog: [Exercise]
        let settings: [UUID: ProgressionSettings]
        let historyStart: Date
        let familiarityStart: Date
    }

    private func loadWorkoutContext(
        today: CalendarDay, now: Date, profile: AthleteProfile?, catalog: [Exercise], loadID: UUID
    ) async {
        guard let workouts else {
            recentWorkouts = nil
            updateStrengthChoices()
            return
        }
        let blocks = profile?.declaredBlocks ?? []
        let rotationStart = today.adding(days: -Self.rotationHistoryDays, calendar: calendar).startDate(in: calendar)
        let blockStart = PlanSchedule.runningBlock(blocks, today: today, calendar: calendar)?.start
            .startDate(in: calendar)
        async let logged = try? workouts.sessions(from: min(rotationStart, blockStart ?? rotationStart), to: now)
        async let allRoutines = try? routines?.allRoutines()
        async let allSettings = try? progression?.allProgressionSettings()
        let (sessions, availableRoutines, settings) = await (logged, allRoutines, allSettings)
        guard activeLoad == loadID else { return }
        let completed = (sessions ?? []).filter { RecentTraining.isCompleted($0, through: now) && $0.startedAt < now }
        let recent = completed.filter { $0.startedAt >= rotationStart }
        let assignment = profile?.goal.flatMap { $0.kind == .hybrid ? $0 : nil }?.scheduledStrength
            .first { $0.day == today }
        let routine: Routine? = if let id = assignment?.routineID {
            availableRoutines?.first { $0.id == id }
        } else if assignment == nil {
            PlanSchedule.next(blocks: blocks, routines: availableRoutines ?? [], sessions: completed, today: today,
                              calendar: calendar)?.routine
        } else {
            nil
        }
        if chosenWorkout?.day != today { chosenWorkout = nil }
        recentWorkouts = WorkoutContext(
            sessions: recent, catalog: catalog, settings: settings ?? [:],
            rotation: SessionRotation.detect(in: recent),
            planned: routine.map { SessionRotation.Slot(id: $0.id.uuidString, name: $0.name) },
            recent: SessionRotation.recentWorkouts(in: recent)
        )
        updateStrengthChoices()
    }

    /// The workout that comes next: the athlete's choice for today, the plan's next routine, or the rotation's next.
    private var nextWorkout: StrengthOption.Basis? {
        guard let context = recentWorkouts, context.planned == nil else { return nil }
        if let chosen = chosenWorkout, let slot = strengthChoices.first(where: { $0.id == chosen.id }) {
            return .chosen(SessionRotation.Slot(id: slot.id, name: slot.title))
        }
        return context.rotation.map { .rotation($0.next) }
    }

    private func updateStrengthChoices() {
        guard let context = recentWorkouts, context.planned == nil else {
            strengthChoices = []
            strengthChoiceNote = nil
            return
        }
        let slots = context.rotation?.order ?? context.recent
        strengthChoices = slots.count >= 2 ? slots.map { StrengthChoice(id: $0.id, title: $0.name) } : []
        let selected = chosenWorkout?.id ?? context.rotation?.next.id
        strengthChoices = strengthChoices.map {
            StrengthChoice(id: $0.id, title: $0.title, isSelected: $0.id == selected)
        }
        if let rotation = context.rotation, rotation.order.count >= 2 {
            let cycle = rotation.order.map(\.name).joined(separator: " → ")
            strengthChoiceNote = L10n.format("You rotate through {1}. Next up: {2}.", cycle, rotation.next.name)
        } else if strengthChoices.count >= 2 {
            strengthChoiceNote = L10n.text(
                "Your recent sessions don't follow a fixed order yet. Choose the one you plan to do."
            )
        } else {
            strengthChoiceNote = nil
        }
    }

    private func rebuildStrengthOption() {
        guard let inputs = strengthInputs else { return }
        let routine = inputs.assignedRoutine ?? inputs.plannedRoutine
        strengthOption = StrengthOption.make(
            routine: routine, isDated: inputs.assignedRoutine != nil, sessions: inputs.sessions,
            exercises: inputs.catalog, settings: inputs.settings, historyStart: inputs.historyStart,
            familiarityStart: inputs.familiarityStart, basis: routine == nil ? nextWorkout : nil
        )
    }

    /// The deload applied to the session that comes next. Without one, Today explains it in general terms.
    private func updateDeloadSession() {
        deloadSession = nil
        guard let advice = deloadAdvice, let context = recentWorkouts else { return }
        if case .confirmBreak = advice.state { return }
        let target: (slot: SessionRotation.Slot, heading: String)
        if let planned = context.planned {
            target = (planned, L10n.format("Next in your plan: {1}", planned.name))
        } else if let basis = nextWorkout {
            switch basis {
            case let .rotation(slot): target = (slot, L10n.format("Next in your rotation: {1}", slot.name))
            case let .chosen(slot): target = (slot, L10n.format("Your choice: {1}", slot.name))
            }
        } else {
            return
        }
        guard let session = context.sessions.filter({ SessionRotation.slot(for: $0).id == target.slot.id })
            .max(by: { $0.startedAt < $1.startedAt }) else { return }
        deloadSession = DeloadSessionPreview.make(
            heading: target.heading, session: session, exercises: context.catalog, settings: context.settings,
            format: format
        )
    }

    /// The deload card holds the next-session choice when it shows; the strength option has it otherwise.
    public var showsNextSessionInDeload: Bool { deloadHowTo != nil }

    /// How to apply the deload: to the next session shown below, or to any session when the app cannot tell which.
    public var deloadHowTo: String? {
        guard let advice = deloadAdvice else { return nil }
        if case .confirmBreak = advice.state { return nil }
        if deloadSession != nil {
            return L10n.text("Apply it to every session of the week, starting with the next one:")
        }
        return L10n.text(
            "Every session this week: for example, 4 × 6 at 100 kg becomes 2 × 6 at 90 kg, with at least 3 reps left."
        )
    }

    nonisolated private static func readRecentRuns(
        sources: [any MetricsSource], from start: Date, to end: Date
    ) async -> (activities: [RunActivity], failed: Bool) {
        await withTaskGroup(of: [RunActivity]?.self) { group in
            for source in sources {
                group.addTask { try? await source.runs(from: start, to: end) }
            }
            var activities: [RunActivity] = []
            var failed = false
            for await result in group {
                if let result { activities += result } else { failed = true }
            }
            return (activities, failed)
        }
    }

    /// Asks every source for access (the Apple Health permission sheet), then reloads.
    public func connectHealth(now: Date = .now) async {
        accessError = nil
        for source in sources {
            do {
                try await source.requestAccess()
            } catch {
                accessError = L10n.format(
                    "{1} could not ask for permission: {2}", source.kind.displayName, error.localizedDescription
                )
            }
        }
        await load(now: now)
    }

    private func text(for reason: ReadinessReason) -> String {
        switch reason {
        case .markedSick:
            L10n.text("Marked as sick in today's check-in. Rest until the symptoms ease.")
        case .symptomsLimitTraining:
            L10n.text("You reported symptoms that make you feel too unwell to train.")
        case .exerciseWarningSigns:
            L10n.text("Symptoms to discuss with a clinician")
        case .runningPainLimitsTraining:
            L10n.text("Running pain worsened or affected your stride")
        case .unusualFatigue:
            L10n.text("More fatigue than usual")
        case .unusualStress:
            L10n.text("More stress than usual")
        case .hrvBelowBaseline(let nights):
            if let coverage = readiness.hrvCoverage, let metric = coverage.metric {
                L10n.format(
                    "HRV ({1}) below your usual range ({2} of {3} comparable readings low in the last {4} days).",
                    metric.seriesLabel, String(nights), String(coverage.recentReadings), String(coverage.recentDays)
                )
            } else {
                L10n.text("HRV below your usual range.")
            }
        case .hrvMayReflectCycle:
            L10n.text("HRV is normally lower in the second half of the menstrual cycle, so this alone does not make the light red.")
        case .phaseBaseline(.follicular, let cycles):
            L10n.format("Compared with your follicular days in the last {1} cycles.", cycles)
        case .phaseBaseline(.luteal, let cycles):
            L10n.format("Compared with your luteal days in the last {1} cycles.", cycles)
        case .possibleLutealShift:
            L10n.text("Resting HR often rises a few beats before a period; the threshold allows for it.")
        case .restingHeartRateElevated(let bpm):
            L10n.format("Resting HR {1} bpm above your usual.", format.number(bpm, maxFractionDigits: 0))
        case .shortSleep(let hours):
            L10n.format("Short sleep: {1} h.", format.number(hours, maxFractionDigits: 1))
        case .lowEnergy(let score):
            L10n.format("Low energy in today's check-in ({1}/5).", String(score))
        case .highSoreness(let score):
            L10n.format("Sore muscles in today's check-in ({1}/3).", String(score))
        case .missingData:
            L10n.text("It needs about two weeks of HRV or resting HR from Apple Health, last night's sleep or a check-in.")
        }
    }

    private func has(_ value: (DailyMetrics) -> Double?) -> Bool {
        metrics.flatMap(value) != nil || week.contains { value($0) != nil }
    }

    private func average(_ value: (DailyMetrics) -> Double?) -> Double? {
        let values = week.compactMap(value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func weekly(_ value: String) -> String {
        L10n.format("7-day avg {1}", value)
    }
}
