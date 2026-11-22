import Analytics
import Domain
import Foundation

/// Reads the inputs shared by Today and the context export. The export can extend the windows for its own rows.
public struct TrainingRecordLoader: Sendable {
    public static let historyDays = DeloadDetection.historyDays
    public static let cycleDays = 365

    private let sources: SourceReader
    private let activity: [any ActivitySource]
    private let checkIns: (any CheckInRepository)?
    private let workouts: (any WorkoutRepository)?
    private let exercises: (any ExerciseRepository)?
    private let recordedStrength: (any RecordedStrengthSource)?
    private let routines: (any RoutineRepository)?
    private let progression: (any ProgressionSettingsRepository)?
    private let cycle: (any CycleSource)?

    public init(
        sources: [any MetricsSource], activity: [any ActivitySource], checkIns: (any CheckInRepository)?,
        workouts: (any WorkoutRepository)?, exercises: (any ExerciseRepository)?,
        recordedStrength: (any RecordedStrengthSource)?, routines: (any RoutineRepository)?,
        progression: (any ProgressionSettingsRepository)?, cycle: (any CycleSource)?
    ) {
        self.sources = SourceReader(sources: sources)
        self.activity = activity
        self.checkIns = checkIns
        self.workouts = workouts
        self.exercises = exercises
        self.recordedStrength = recordedStrength
        self.routines = routines
        self.progression = progression
        self.cycle = cycle
    }

    public struct Snapshot: Sendable {
        public let record: TrainingRecord
        public let walkOriginals: [WalkBout]
        public let runOriginals: [RunActivity]
        public let strengthOriginals: [RecordedStrengthActivity]
        public let metrics: SourceReading<[DailyMetrics]>
        public let metricsBySource: [DailyMetrics]
        public let allSessions: [StrengthSession]
        public let allCheckIns: [CheckIn]
        public let checkIn: CheckIn?
        public let sessionsFailed: Bool
        public let settingsFailed: Bool
        public let localReadFailed: Bool

        public func assessment(
            profile: AthleteProfile?, now: Date, settings: ReadinessRules.Settings = .init(),
            calendar: Calendar = .current
        ) -> DailyAssessment {
            DailyAssessment(
                record: record, profile: profile, checkIn: checkIn, now: now,
                settings: settings, calendar: calendar
            )
        }
    }

    public func load(
        now: Date, profile: AthleteProfile?, exportFrom: CalendarDay? = nil,
        settings: ReadinessRules.Settings = .init(), calendar: Calendar = .current
    ) async -> Snapshot {
        let today = CalendarDay(now, calendar: calendar)
        let stressStart = today.adding(days: -(RecoveryTrend.stressWindowDays - 1), calendar: calendar)
        let historyStart = today.adding(days: -Self.historyDays, calendar: calendar).startDate(in: calendar)
        let blockStart = PlanSchedule.runningBlock(profile?.declaredBlocks ?? [], today: today, calendar: calendar)?
            .start.startDate(in: calendar)
        let exportStart = exportFrom?.adding(days: -365, calendar: calendar).startDate(in: calendar)
        let recoveryStart: Date = profile?.countsBreaksAutomatically == true ? .distantPast : historyStart
        let sessionStart = min(historyStart, blockStart ?? historyStart, exportStart ?? historyStart)
        let sessionReadStart = min(sessionStart, recoveryStart)
        let metricsRange = ReadinessAssessment.historyRange(
            today: today, tracksCycle: cycle != nil && profile?.usesCyclePhase == true,
            settings: settings, calendar: calendar
        )

        async let logged = try? workouts?.sessions(from: sessionReadStart, to: now)
        async let catalog = try? exercises?.allExercises()
        async let stored = try? progression?.allProgressionSettings()
        async let templates = try? routines?.allRoutines()
        // Read across midnight before matching. The assessment keeps its original input window.
        let activityStart = calendar.date(byAdding: .day, value: -1, to: recoveryStart) ?? recoveryStart
        async let runs = sources.runOriginals(from: activityStart, to: now)
        async let recordings = recordedStrength?.strengthActivities(from: activityStart, to: now)
        let metricsStart = min(metricsRange.lowerBound, exportFrom ?? today)
        async let allMetrics = sources.dailyMetricsBySource(in: metricsStart...today)
        let checkInStart = min(stressStart, exportFrom ?? today)
        async let checkInHistory = try? checkIns?.checkIns(in: checkInStart...today)
        async let current = try? checkIns?.checkIn(for: today)
        async let cycleContext = readCycle(profile: profile, today: today, calendar: calendar)
        async let walks = readMovement(today: today, calendar: calendar)

        let reading = await allMetrics
        let metrics = SourceReader.mergedDailyMetrics(reading)
        let historyMetrics = metrics.value.filter { metricsRange.contains($0.day) }
        let activity = await walks
        let walkOriginals = activity.flatMap(\.walks).filter {
            $0.durationSeconds.isFinite && $0.durationSeconds > 0 && $0.end <= now
        }
        let movement = Self.mergeMovement(history: historyMetrics, activity: activity, walks: walkOriginals,
                                          calendar: calendar)
        let (sessions, exercises, progression, routines) = await (logged, catalog, stored, templates)
        let (runReading, strength, checkIns, latest) = await (runs, recordings, checkInHistory, current)
        let checkIn = latest.flatMap { $0.day == today ? $0 : nil } ?? checkIns?.last { $0.day == today }
        let history = (checkIns ?? []).filter { $0.day != today }
        let recent = history.filter { (stressStart...today).contains($0.day) } + (checkIn.map { [$0] } ?? [])
        let record = TrainingRecord(
            sessions: (sessions ?? []).filter { $0.isCompleted(through: now) },
            exercises: exercises ?? [], settings: progression ?? [:], routines: routines ?? [],
            runs: RunDeduplication.removingDuplicates(runReading.value.filter { $0.startedAt >= recoveryStart }),
            runReadFailed: runReading.failed,
            recordings: StrengthActivityMatching.removingDuplicates(
                (strength ?? []).filter { $0.startedAt >= recoveryStart }
            ),
            metrics: historyMetrics, checkIns: recent, activity: movement,
            cycle: await cycleContext
        )
        let sessionsFailed = workouts != nil && sessions == nil
        let settingsFailed = self.progression != nil && progression == nil
        return Snapshot(
            record: record, walkOriginals: walkOriginals,
            runOriginals: runReading.value, strengthOriginals: strength ?? [],
            metrics: metrics, metricsBySource: reading.value,
            allSessions: (sessions ?? []).filter { $0.startedAt >= sessionStart },
            allCheckIns: history + (checkIn.map { [$0] } ?? []), checkIn: checkIn,
            sessionsFailed: sessionsFailed, settingsFailed: settingsFailed,
            localReadFailed: sessionsFailed || settingsFailed || (self.exercises != nil && exercises == nil)
                || (self.routines != nil && routines == nil)
        )
    }

    private func readCycle(profile: AthleteProfile?, today: CalendarDay, calendar: Calendar) async -> CycleContext? {
        guard let profile, profile.usesCyclePhase, let cycle else { return nil }
        let range = today.adding(days: -Self.cycleDays, calendar: calendar)...today
        let events = (try? await cycle.menstrualEvents(in: range)) ?? []
        return CycleContext(mode: profile.cycleTracking, events: events)
    }

    private func readMovement(today: CalendarDay, calendar: Calendar) async -> [DailyActivity] {
        let start = today.adding(
            days: Workload.usualStartOffset - EverydayMovement.Settings().baselineDays, calendar: calendar
        )
        var readings: [DailyActivity] = []
        for source in activity {
            readings += (try? await source.dailyActivity(in: start...today)) ?? []
        }
        return readings.filter { (start...today).contains($0.day) }
    }

    private static func mergeMovement(
        history: [DailyMetrics], activity: [DailyActivity], walks: [WalkBout], calendar: Calendar
    ) -> [DailyActivity] {
        let walksByDay = Dictionary(grouping: EverydayMovement.removingDuplicateWalks(walks)) {
            CalendarDay($0.start, calendar: calendar)
        }
        var steps: [CalendarDay: Int] = [:]
        for entry in activity.reversed() { steps[entry.day] = entry.steps ?? steps[entry.day] }
        for entry in history { steps[entry.day] = entry.steps ?? steps[entry.day] }
        let days = Set(steps.keys).union(walksByDay.keys)
        return days.sorted().map { DailyActivity(day: $0, steps: steps[$0], walks: walksByDay[$0] ?? []) }
    }
}
