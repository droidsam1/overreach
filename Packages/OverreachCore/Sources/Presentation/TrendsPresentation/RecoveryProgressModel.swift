import Analytics
import Domain
import Foundation
import Observation
import PresentationKit
import TrainingServices

/// State of "Recovery & Progress" (ADR-0014): recovery readings and recent load, read from the same sources and
/// judged by the same rules as Today (ADR-0035), so both screens agree for the same readings.
@MainActor
@Observable
public final class RecoveryProgressModel {
    public typealias RunningSegmentLoader =
        @Sendable ([RunActivity]) async -> [ComparableRunningHeartRate.Segment]

    /// The sections of the screen. Today opens `.recovery` directly and Plan opens `.progress`.
    public enum Section: String, Hashable, Sendable, CaseIterable {
        case recovery, recentLoad, progress
    }

    public private(set) var readings: [RecoveryReading] = []
    /// Usual sleep and training times with their observations; `nil` until there is enough data (ADR-0045).
    public private(set) var sleepTiming: SleepTimingCard?
    public private(set) var loadRows: [RecentLoadRow] = []
    public private(set) var weeklyLoad: WeeklyLoadReading?
    /// The interval of the trend charts, shared by the Recovery and Recent load details.
    public private(set) var trendRange = TrendRange.days30
    public private(set) var recoveryCharts: [TrendChart] = []
    public private(set) var weeklyCharts: [TrendChart] = []
    public private(set) var showsRecoveryTrends = false
    public private(set) var showsLoadTrends = false
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false
    /// "Apple Health: <system message>" for each source that failed in the last load. Available data stays visible.
    public private(set) var failureLines: [String] = []
    public private(set) var trainingReadNote: String?
    /// Whether a Garmin account is connected (ADR-0022).
    public private(set) var isGarminConnected = false
    private var wearsGarmin = false
    private var hasGoal = false
    private var sessionsOfMostTrainedLift = 0

    public private(set) var newSectionHints: [String] = []
    private let sectionHints: SectionHints

    public var sectionHintCandidates: [SectionHints.Section]? {
        guard hasLoaded, !isLoading, !showsFailure, trainingReadNote == nil else { return nil }
        var available: [SectionHints.Section] = []
        if showsRecovery { available.append(.recovery) }
        if showsRecentLoad { available.append(.recentLoad) }
        if showsProgress { available.append(.progress) }
        return available
    }

    public func updateSectionHints(includesProgress: Bool) {
        guard let candidates = sectionHintCandidates else { return }
        let visible = includesProgress ? candidates : candidates.filter { $0 != .progress }
        let hints = sectionHints.update(visible, on: .recoveryProgress)
        if !hints.isEmpty { newSectionHints = hints }
    }

    private let recordLoader: TrainingRecordLoader
    private let garmin: (any GarminAccount)?
    private let profiles: (any ProfileRepository)?
    private let readinessSettings: ReadinessRules.Settings
    private let calendar: Calendar
    private let format: Format
    private var activeLoad: UUID?
    private var trendInputs: TrendInputs?
    private let runChoices: @MainActor () -> [RunMatchPair: RunMatchChoice]
    private var performanceInputs: PerformanceInputs?
    private let runningSegments: RunningSegmentLoader
    private let runningTrack: @Sendable (RunActivity) async -> RunningTrack?
    private let savePulseSensors: @MainActor ([String: String]) -> Void
    private var pulseSensors: [String: String]

    private struct PerformanceInputs {
        let today: CalendarDay
        let now: Date
        let profile: AthleteProfile?
        let runResults: [PerformanceDistance: [RunningPerformance.BestTime]]
        let runningSegments: [ComparableRunningHeartRate.Segment]
        let runningBlocks: [RunningBlockComparison.Result]
        let metrics: [DailyMetrics]
        let sets: [StrengthPerformance.RecordedSet]
        let exercises: [Exercise]
    }

    public var performanceRange = TrendRange.days90
    public var performanceDistance = PerformanceDistance.fiveKilometers

    public var hasRunningPerformance: Bool {
        guard let inputs = performanceInputs else { return false }
        return inputs.runResults.values.contains { !$0.isEmpty }
            || !inputs.runningSegments.isEmpty || !inputs.runningBlocks.isEmpty
    }
    public var hasStrengthPerformance: Bool { !(performanceInputs?.sets.isEmpty ?? true) }
    public var showsPerformance: Bool { hasRunningPerformance || hasStrengthPerformance }

    public var runningPerformance: [PerformanceSeries] {
        guard let inputs = performanceInputs else { return [] }
        let results = inputs.runResults[performanceDistance] ?? []
        return performance(using: inputs).running(results)
    }

    public var comparableHeartRate: PerformanceSeries? {
        guard let inputs = performanceInputs else { return nil }
        let performance = performance(using: inputs)
        let confirmed = inputs.runningBlocks.map { result in
            result.confirmingSensor(pulseSensor(for: result.run.id).sensorID)
        }
        return performance.runningPulse(confirmed, now: inputs.now, calendar: calendar, metrics: inputs.metrics)
            ?? performance.heartRate(inputs.runningSegments, now: inputs.now, calendar: calendar)
    }

    public var runningPulseSensorRows: [RunningPulseSensorRow] {
        guard let inputs = performanceInputs else { return [] }
        let window = performance(using: inputs).window
        var seen: Set<String> = []
        return inputs.runningBlocks.reversed().compactMap { result in
            let run = result.run
            guard result.sensorID == nil, window.contains(run.startedAt), seen.insert(run.id).inserted else {
                return nil
            }
            return RunningPulseSensorRow(run: run, selection: pulseSensor(for: run.id))
        }
    }

    public var pendingPulseSensorRows: [RunningPulseSensorRow] {
        runningPulseSensorRows.filter { $0.selection == .unknown }
    }

    public var confirmedPulseSensorRows: [RunningPulseSensorRow] {
        runningPulseSensorRows.filter { $0.selection != .unknown }
    }

    public func choosePulseSensor(_ sensor: RunningPulseSensor, for runID: String) {
        guard runningPulseSensorRows.contains(where: { $0.id == runID }) else { return }
        pulseSensors[runID] = sensor == .unknown ? nil : sensor.rawValue
        savePulseSensors(pulseSensors)
    }

    private func pulseSensor(for runID: String) -> RunningPulseSensor {
        pulseSensors[runID].flatMap(RunningPulseSensor.init(rawValue:)) ?? .unknown
    }

    public var strengthPerformanceOptions: [StrengthPerformanceOption] {
        guard let inputs = performanceInputs else { return [] }
        return performance(using: inputs).strengthOptions(inputs.sets, exercises: inputs.exercises)
    }

    public func strengthPerformance(
        for option: StrengthPerformanceOption, source: DataSourceKind? = nil
    ) -> [PerformanceSeries] {
        guard let inputs = performanceInputs else { return [] }
        return performance(using: inputs).strengthSeries(
            option, source: source, profile: inputs.profile, now: inputs.now, calendar: calendar
        )
    }

    private func performance(using inputs: PerformanceInputs) -> PerformanceProgress {
        var displayFormat = format
        if let profile = inputs.profile { displayFormat.weightUnit = profile.weightUnit }
        return PerformanceProgress(
            window: PerformanceComparison(through: inputs.today, days: performanceRange.days, calendar: calendar),
            format: displayFormat
        )
    }

    /// What the charts are drawn from, kept so changing the interval does not read the sources again.
    private struct TrendInputs {
        let today: CalendarDay
        let metrics: [DailyMetrics]
        let rawMetrics: [DailyMetrics]
        let hrvSeries: HRVSeriesID?
        let record: TrainingRecord
    }

    public init(
        sources: [any MetricsSource], activity: [any ActivitySource] = [], checkIns: (any CheckInRepository)? = nil,
        garmin: (any GarminAccount)? = nil, profiles: (any ProfileRepository)? = nil,
        workouts: (any WorkoutRepository)? = nil, exercises: (any ExerciseRepository)? = nil,
        recordedStrength: (any RecordedStrengthSource)? = nil, routines: (any RoutineRepository)? = nil,
        progression: (any ProgressionSettingsRepository)? = nil, cycle: (any CycleSource)? = nil,
        readinessSettings: ReadinessRules.Settings = ReadinessRules.Settings(), calendar: Calendar = .current,
        format: Format = Format(), sectionHints: SectionHints = SectionHints(),
        runChoices: @escaping @MainActor () -> [RunMatchPair: RunMatchChoice] = { [:] },
        runningSegments: @escaping RunningSegmentLoader = { _ in [] },
        runningTrack: @escaping @Sendable (RunActivity) async -> RunningTrack? = { _ in nil },
        pulseSensors: [String: String] = [:],
        savePulseSensors: @escaping @MainActor ([String: String]) -> Void = { _ in },
        balanceDismissals: MuscleBalanceDismissals = .init()
    ) {
        recordLoader = TrainingRecordLoader(
            sources: sources, activity: activity, checkIns: checkIns, workouts: workouts, exercises: exercises,
            recordedStrength: recordedStrength, routines: routines, progression: progression, cycle: cycle
        )
        self.garmin = garmin
        self.profiles = profiles
        self.readinessSettings = readinessSettings
        self.calendar = calendar
        self.format = format
        self.sectionHints = sectionHints
        self.runChoices = runChoices
        self.runningSegments = runningSegments
        self.runningTrack = runningTrack
        self.pulseSensors = pulseSensors
        self.savePulseSensors = savePulseSensors
        self.balanceDismissals = balanceDismissals
    }

    // MARK: Screen state

    public private(set) var muscleBalanceRows: [MuscleBalanceRow] = []
    private let balanceDismissals: MuscleBalanceDismissals

    public func dismissMuscleBalance(_ id: String) {
        balanceDismissals.dismiss(id, in: MuscleBalanceAudit.historyScope)
        muscleBalanceRows.removeAll { $0.id == id }
    }

    public var showsFailure: Bool { !failureLines.isEmpty }
    /// No reading from any source yet.
    public var hasNoReadings: Bool { hasLoaded && !readings.contains(where: \.isAvailable) }
    public var showsConnectGarmin: Bool {
        garmin != nil && !isGarminConnected && hasLoaded && (wearsGarmin || hasNoReadings)
    }
    /// The Recovery row needs at least one reading (ADR-0041, rule 6), or enough nights or sessions for timing.
    public var showsRecovery: Bool {
        showsRecoveryTrends || sleepTiming != nil
            || SectionAvailability.recovery(readings: readings.filter(\.isAvailable).count)
    }
    /// Recent load needs something logged to compare: a session, a run or everyday movement.
    public var showsRecentLoad: Bool {
        showsLoadTrends || !muscleBalanceRows.isEmpty || SectionAvailability.recentLoad(rows: loadRows.count)
    }
    /// Progress needs a performance observation, a goal, or a lift trained in two sessions.
    public var showsProgress: Bool {
        showsPerformance || SectionAvailability.progress(
            hasGoal: hasGoal, sessionsOfMostTrainedLift: sessionsOfMostTrainedLift
        )
    }
    /// The one line shown instead of the sections while none has data.
    public var unlockHint: String? {
        guard hasLoaded else { return nil }
        return SectionAvailability.unlockHint(
            recovery: showsRecovery, recentLoad: showsRecentLoad, progress: showsProgress
        )
    }

    /// One line for the section row.
    public var recoverySummary: String {
        guard hasLoaded else { return L10n.text("Loading…") }
        let available = readings.filter(\.isAvailable).count
        guard available > 0 else { return L10n.text("No readings yet") }
        return L10n.format("{1} readings available", String(available))
    }

    public var recentLoadSummary: String {
        guard hasLoaded else { return L10n.text("Loading…") }
        guard let first = loadRows.first(where: { $0.kind != .garminEstimate }) ?? loadRows.first else {
            return L10n.text("No training in the last weeks")
        }
        return L10n.format("{1}: {2}", first.title, first.value)
    }

    public func load(now: Date = .now) async {
        let loadID = UUID()
        activeLoad = loadID
        isLoading = true
        newSectionHints = []
        defer {
            if activeLoad == loadID {
                isLoading = false
                activeLoad = nil
            }
        }
        let today = CalendarDay(now, calendar: calendar)
        let profile = try? await profiles?.profile()
        async let garminConnection = garmin?.connection()
        // The longest chart reaches further back than the readiness history, so the metrics window is widened.
        let longest = today.adding(days: 1 - (TrendRange.allCases.map(\.days).max() ?? 90), calendar: calendar)
        let snapshot = await recordLoader.load(
            now: now, profile: profile, exportFrom: longest, settings: readinessSettings, calendar: calendar
        )
        let connected = await garminConnection != nil
        guard activeLoad == loadID else { return }
        let record = snapshot.record
        let runs = RunDeduplication.resolve(snapshot.runOriginals, choices: runChoices()).unambiguousRuns
            .filter { $0.startedAt <= now }
        if !snapshot.localReadFailed {
            let findings = record.muscleBalance(profile: profile, resolvedRuns: runs, now: now, calendar: calendar)
            muscleBalanceRows = balanceDismissals.visible(
                MuscleBalanceAudit.rows(for: findings, format: format), in: MuscleBalanceAudit.historyScope
            )
        } else {
            muscleBalanceRows = []
        }
        async let legacy = runningSegments(runs)
        let comparison = PerformanceComparison(through: today, days: TrendRange.days90.days, calendar: calendar)
        let blocks = await Self.loadRunningBlocks(
            runs.filter { $0.source == .garmin && $0.kind == .training && comparison.contains($0.startedAt) },
            from: runningTrack, maxHeartRate: profile?.maxHeartRate
        )
        let segments = await legacy
        guard activeLoad == loadID else { return }
        let tracks = await Self.loadTracks(
            runs.filter { $0.source == .garmin && comparison.contains($0.startedAt) }, from: runningTrack
        )
        guard activeLoad == loadID else { return }
        let results = Dictionary(uniqueKeysWithValues: PerformanceDistance.allCases.map { distance in
            (distance, RunningPerformance.bestTimes(for: distance.distance, runs: runs, tracks: tracks))
        })
        performanceInputs = PerformanceInputs(
            today: today, now: now, profile: profile, runResults: results, runningSegments: segments,
            runningBlocks: blocks, metrics: snapshot.metrics.value,
            sets: StrengthPerformance.recordedSets(in: record.sessions, through: now),
            exercises: record.exercises
        )
        let readiness = ReadinessAssessment.assess(
            today: today, history: record.metrics, checkIn: snapshot.checkIn, profile: profile, cycle: record.cycle,
            settings: readinessSettings, calendar: calendar
        )
        hasGoal = profile?.goal != nil
        sessionsOfMostTrainedLift = Dictionary(
            record.sessions.flatMap { Set($0.entries.map(\.exerciseID)) }.map { ($0, 1) }, uniquingKeysWith: +
        ).values.max() ?? 0
        readings = RecoveryReadings(calendar: calendar, format: format)
            .readings(readiness: readiness, history: record.metrics, today: today)
        sleepTiming = SleepTimingCard(
            SleepTrainingTiming.report(
                metrics: snapshot.metrics.value, sessions: record.sessions, runs: runs, recordings: record.recordings,
                now: now, calendar: calendar
            ),
            format: format
        )
        loadRows = RecentLoad(calendar: calendar, format: format).rows(record: record, today: today)
        weeklyLoad = profile.flatMap {
            record.weeklyLoad(profile: $0, today: today, calendar: calendar)
        }.map { WeeklyLoadReading($0, format: format) }
        var hrvSeries: HRVSeriesID?
        if case let .hrv(series?)? = readiness.hrvInput?.input { hrvSeries = series }
        if hrvSeries == nil {
            hrvSeries = snapshot.metricsBySource.reversed().lazy.compactMap { entry in
                HRVSeriesID.all.first {
                    entry.sources.contains($0.metric.source) && entry.hrvWindow($0.metric) == $0.window
                        && entry.hrv($0.metric).map(self.readinessSettings.plausibleHRVMs.contains) == true
                }
            }.first
        }
        let inputs = TrendInputs(
            today: today, metrics: snapshot.metrics.value, rawMetrics: snapshot.metricsBySource,
            hrvSeries: hrvSeries, record: record
        )
        trendInputs = inputs
        let longestCharts = makeCharts(.days90, inputs: inputs)
        showsRecoveryTrends = longestCharts.recovery.contains(where: \.hasData)
        showsLoadTrends = longestCharts.weekly.contains(where: \.hasData)
        rebuildCharts()
        failureLines = snapshot.metrics.failures.map { "\($0.source.displayName): \($0.reason)" }
        trainingReadNote = record.runReadFailed || snapshot.sessionsFailed
            ? L10n.text("Some recent workouts could not be loaded.") : nil
        isGarminConnected = connected
        wearsGarmin = profile?.wearables.contains(.garmin) ?? false
        hasLoaded = true
    }

    private nonisolated static func loadTracks(
        _ runs: [RunActivity], from source: @Sendable (RunActivity) async -> RunningTrack?
    ) async -> [String: RunningTrack] {
        var tracks: [String: RunningTrack] = [:]
        for run in runs {
            guard !Task.isCancelled else { break }
            if let track = await source(run) { tracks[run.id] = track }
        }
        return tracks
    }

    private nonisolated static func loadRunningBlocks(
        _ runs: [RunActivity], from source: @Sendable (RunActivity) async -> RunningTrack?, maxHeartRate: Double?
    ) async -> [RunningBlockComparison.Result] {
        var results: [RunningBlockComparison.Result] = []
        for run in runs {
            guard !Task.isCancelled else { break }
            if let track = await source(run) {
                results += RunningBlockComparison.observations(for: run, track: track, maxHeartRate: maxHeartRate)
            }
        }
        return results
    }

    /// Shows the charts for another interval from the data already read.
    public func selectTrendRange(_ range: TrendRange) {
        trendRange = range
        rebuildCharts()
    }

    private func rebuildCharts() {
        guard let inputs = trendInputs else { return }
        let charts = makeCharts(trendRange, inputs: inputs)
        recoveryCharts = charts.recovery
        weeklyCharts = charts.weekly
    }

    private func makeCharts(
        _ range: TrendRange, inputs: TrendInputs
    ) -> (recovery: [TrendChart], weekly: [TrendChart]) {
        let charts = TrendCharts(calendar: calendar, format: format, settings: readinessSettings)
        return (
            charts.recovery(
                range: range, today: inputs.today, metrics: inputs.metrics, rawMetrics: inputs.rawMetrics,
                hrvSeries: inputs.hrvSeries
            ),
            charts.weekly(range: range, today: inputs.today, record: inputs.record)
        )
    }
}
