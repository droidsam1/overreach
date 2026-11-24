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
    /// The sections of the screen. Today opens `.recovery` directly and Plan opens `.progress`.
    public enum Section: String, Hashable, Sendable, CaseIterable {
        case recovery, recentLoad, progress
    }

    public private(set) var readings: [RecoveryReading] = []
    public private(set) var loadRows: [RecentLoadRow] = []
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
        format: Format = Format(), sectionHints: SectionHints = SectionHints()
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
    }

    // MARK: Screen state

    public var showsFailure: Bool { !failureLines.isEmpty }
    /// No reading from any source yet.
    public var hasNoReadings: Bool { hasLoaded && !readings.contains(where: \.isAvailable) }
    public var showsConnectGarmin: Bool {
        garmin != nil && !isGarminConnected && hasLoaded && (wearsGarmin || hasNoReadings)
    }
    /// The Recovery row needs at least one reading (ADR-0041, rule 6).
    public var showsRecovery: Bool {
        showsRecoveryTrends || SectionAvailability.recovery(readings: readings.filter(\.isAvailable).count)
    }
    /// Recent load needs something logged to compare: a session, a run or everyday movement.
    public var showsRecentLoad: Bool { showsLoadTrends || SectionAvailability.recentLoad(rows: loadRows.count) }
    /// Progress needs a goal or a lift trained in two sessions.
    public var showsProgress: Bool {
        SectionAvailability.progress(hasGoal: hasGoal, sessionsOfMostTrainedLift: sessionsOfMostTrainedLift)
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
        loadRows = RecentLoad(calendar: calendar, format: format).rows(record: record, today: today)
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
