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
    /// "Learn more" for this reason (ADR-0027); often empty.
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
    public private(set) var recentTrainingDays: [RecentTrainingDay] = []
    public private(set) var strengthOption: StrengthOption?
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
        if readiness.reasons.contains(.symptomsLimitTraining) {
            return L10n.text("Skip training today and reassess how you feel.")
        }
        return switch readiness.level {
        case .green: L10n.text("Train as planned.")
        case .amber: L10n.text("Keep it easy today. Run at a pace you can talk at, or lift with light effort.")
        case .red: L10n.text("Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        case .unknown: L10n.text("Not enough data yet to judge today.")
        }
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
        guard let coverage = readiness.hrvCoverage, !coverage.canCompare else { return nil }
        if coverage.baselineReadings < coverage.minimumBaselineReadings {
            return L10n.format(
                "Still building your usual HRV range ({1} of {2} comparable readings needed).",
                String(coverage.baselineReadings), String(coverage.minimumBaselineReadings)
            )
        }
        return L10n.format(
            "Too few comparable HRV readings in the last {1} days ({2} available, {3} needed).",
            String(coverage.recentDays), String(coverage.recentReadings), String(coverage.minimumRecentReadings)
        )
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

    public var trainingTimelineNote: String? {
        if trainingReadFailed { return L10n.text("Some recent workouts could not be loaded.") }
        if !recentTrainingDays.isEmpty && recentTrainingDays.allSatisfy({ $0.workouts.isEmpty }) {
            return L10n.text("No completed workouts found in the last 7 days.")
        }
        return nil
    }

    public var showsTrainingTimeline: Bool { !recentTrainingDays.isEmpty || trainingReadFailed }

    /// The check-in button only shows when check-ins can be stored.
    public var showsCheckIn: Bool { checkIns != nil }
    public var checkInButtonTitle: String {
        if let title = CheckInModel.title(for: suggestedContextQuestion) { return title }
        return checkIn == nil ? L10n.text("How do you feel today?") : L10n.text("Edit today's check-in")
    }

    private var suggestedContextQuestion: CheckIn.Context.Question? {
        guard checkIn?.context == nil else { return nil }
        return ReadinessRules.contextQuestion(for: readiness)
    }

    /// "Energy 4/5 · Soreness 1/3", or "Sick" — what today's check-in said.
    public var checkInSummary: String? {
        guard let checkIn else { return nil }
        if checkIn.isSick { return L10n.text("Sick") }
        var parts: [String] = []
        if let energy = checkIn.energy { parts.append(L10n.format("Energy {1}/5", String(energy))) }
        if let soreness = checkIn.soreness { parts.append(L10n.format("Soreness {1}/3", String(soreness))) }
        switch checkIn.context?.answer == .yes ? checkIn.context?.question : nil {
        case .symptoms: parts.append(L10n.text("New symptoms affect training"))
        case .stress: parts.append(L10n.text("More stress than usual"))
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

    /// "7-day avg 42 ms", from the days that have a value of the same statistic as the latest (RMSSD and SDNN are not
    /// averaged together, ADR-0024).
    public var hrvCaption: String? {
        let latest = ([metrics].compactMap { $0 } + week.reversed()).first { $0.hrvNightlyAverageMs != nil }
        guard let latest else { return nil }
        return average { $0.hrvMetric == latest.hrvMetric ? $0.hrvNightlyAverageMs : nil }
            .map { weekly(format.number($0, maxFractionDigits: 0) + " ms") }
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
    public init(
        sources: [any MetricsSource], checkIns: (any CheckInRepository)? = nil, backup: (any BackupService)? = nil,
        garmin: (any GarminAccount)? = nil, profiles: (any ProfileRepository)? = nil,
        workouts: (any WorkoutRepository)? = nil, exercises: (any ExerciseRepository)? = nil,
        recordedStrength: (any RecordedStrengthSource)? = nil, routines: (any RoutineRepository)? = nil,
        progression: (any ProgressionSettingsRepository)? = nil,
        readinessSettings: ReadinessRules.Settings = ReadinessRules.Settings(), calendar: Calendar = .current,
        format: Format = Format()
    ) {
        self.sources = sources
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
        strengthOption = nil
        defer {
            if activeLoad == loadID {
                isLoading = false
                activeLoad = nil
            }
        }

        let today = CalendarDay(now, calendar: calendar)
        // The readiness baselines need weeks of history; the screen shows the last 7 days.
        let historyDays = max(6, readinessSettings.baselineDays)
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
        let profile = try? await profiles?.profile()
        guard activeLoad == loadID else { return }
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
            tracksNaturalCycle: profile?.usesCyclePhase ?? false, calendar: calendar
        )
        await loadRecentTraining(in: weekStart...today, now: now, sources: availableSources, profile: profile,
                                 loadID: loadID)
    }

    private func loadRecentTraining(
        in range: ClosedRange<CalendarDay>, now: Date, sources: [any MetricsSource], profile: AthleteProfile?,
        loadID: UUID
    ) async {
        // Include the previous day so copies across midnight can match before filtering to the visible week.
        let start = range.lowerBound.adding(days: -1, calendar: calendar).startDate(in: calendar)
        async let logged = try? workouts?.sessions(from: start, to: now)
        async let catalog = try? exercises?.allExercises()
        async let watch = recordedStrength?.strengthActivities(from: start, to: now)
        async let checkInHistory = try? checkIns?.checkIns(in: range)
        async let runs = Self.readRecentRuns(sources: sources, from: start, to: now)
        let (sessions, allExercises, recordings, previousCheckIns, runResult) = await (
            logged, catalog, watch, checkInHistory, runs
        )
        guard activeLoad == loadID else { return }
        trainingReadFailed = runResult.failed || (workouts != nil && sessions == nil)
        let currentCheckIn = checkIn.map { [$0] } ?? []
        recentTrainingDays = RecentTraining(calendar: calendar, format: format).days(
            in: range, through: now, metrics: week, checkIns: currentCheckIn + (previousCheckIns ?? []),
            runs: runResult.activities, sessions: sessions ?? [], recordings: recordings ?? [], exercises: allExercises ?? []
        )
        guard readiness.level == .amber, let sessions,
              !hasStrengthToday(sessions: sessions, recordings: recordings ?? [], now: now) else { return }
        await loadStrengthOption(today: range.upperBound, now: now, profile: profile, catalog: allExercises ?? [],
                                 loadID: loadID)
    }

    private func hasStrengthToday(sessions: [StrengthSession], recordings: [RecordedStrengthActivity], now: Date) -> Bool {
        let start = calendar.startOfDay(for: now)
        return sessions.contains { $0.startedAt <= now && ($0.endedAt ?? $0.startedAt) >= start }
            || recordings.contains { $0.durationSeconds.isFinite && (start...now).contains($0.endedAt) }
    }

    private func loadStrengthOption(
        today: CalendarDay, now: Date, profile: AthleteProfile?, catalog: [Exercise], loadID: UUID
    ) async {
        let blocks = profile?.declaredBlocks ?? []
        let historyStart = now.addingTimeInterval(-ProgressionTargets.historyWindow)
        let blockStart = PlanSchedule.runningBlock(blocks, today: today, calendar: calendar)?.start.startDate(in: calendar)
        async let history = try? workouts?.sessions(from: min(historyStart, blockStart ?? historyStart), to: now)
        async let allRoutines = try? routines?.allRoutines()
        async let allSettings = try? progression?.allProgressionSettings()
        let (sessions, availableRoutines, settings) = await (history, allRoutines, allSettings)
        guard activeLoad == loadID, let sessions, !hasStrengthToday(sessions: sessions, recordings: [], now: now)
        else { return }
        let completed = sessions.filter { RecentTraining.isCompleted($0, through: now) }
        let planned = PlanSchedule.next(blocks: blocks, routines: availableRoutines ?? [], sessions: completed,
                                        today: today, calendar: calendar)
        let familiarityStart = today.adding(days: -EasyStrengthAdjustment.familiarityDays, calendar: calendar)
            .startDate(in: calendar)
        strengthOption = StrengthOption.make(
            routine: progression != nil && settings == nil ? nil : planned?.routine, sessions: completed,
            exercises: catalog, settings: settings ?? [:], historyStart: historyStart, familiarityStart: familiarityStart
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
        case .hrvBelowBaseline(let nights):
            if let coverage = readiness.hrvCoverage {
                L10n.format(
                    "HRV below your usual range ({1} of {2} comparable readings low in the last {3} days).",
                    String(nights), String(coverage.recentReadings), String(coverage.recentDays)
                )
            } else {
                L10n.text("HRV below your usual range.")
            }
        case .hrvMayReflectCycle:
            L10n.text("HRV is normally lower in the second half of the menstrual cycle, so this alone does not make the light red.")
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
