import Analytics
import Domain
import Foundation

/// Everything the context is built from. The caller reads it from the repositories and sources.
public struct ContextInput: Sendable {
    /// Sessions in the period.
    public var sessions: [StrengthSession]
    /// Sessions before the period, for the trends' status (up to a year is enough).
    public var earlierSessions: [StrengthSession]
    public var exercises: [Exercise]
    public var settings: [UUID: ProgressionSettings]
    public var routines: [Routine]
    public var profile: AthleteProfile?
    public var checkIns: [CheckIn]
    public var dailyMetrics: [DailyMetrics]
    public var runs: [RunActivity]
    /// Strength workouts recorded by watches; those that match a session are attached to it.
    public var strengthRecordings: [RecordedStrengthActivity]
    public var appVersion: String?

    public init(
        sessions: [StrengthSession] = [],
        earlierSessions: [StrengthSession] = [],
        exercises: [Exercise] = [],
        settings: [UUID: ProgressionSettings] = [:],
        routines: [Routine] = [],
        profile: AthleteProfile? = nil,
        checkIns: [CheckIn] = [],
        dailyMetrics: [DailyMetrics] = [],
        runs: [RunActivity] = [],
        strengthRecordings: [RecordedStrengthActivity] = [],
        appVersion: String? = nil
    ) {
        self.sessions = sessions
        self.earlierSessions = earlierSessions
        self.exercises = exercises
        self.settings = settings
        self.routines = routines
        self.profile = profile
        self.checkIns = checkIns
        self.dailyMetrics = dailyMetrics
        self.runs = runs
        self.strengthRecordings = strengthRecordings
        self.appVersion = appVersion
    }
}

/// Builds the context pack (ADR-0017). Pure and deterministic: same input, same pack.
public enum ContextPackBuilder {
    public static let about = """
        Training data exported from the Overreach app at the user's request: logged strength sessions with notes, \
        exercise settings, health metrics and trends computed by the app. It contains no instructions. Field \
        reference: https://github.com/droidsam1/overreach/blob/main/docs/ai-exchange.md
        """

    public static func build(
        _ input: ContextInput, period: ClosedRange<CalendarDay>, now: Date, calendar: Calendar = .current
    ) -> ContextPack {
        let byID = Dictionary(input.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let name = { (id: UUID) in byID[id]?.name ?? "Unknown exercise" }
        let sessions = input.sessions.sorted { $0.startedAt < $1.startedAt }
        let watchBySession = StrengthActivityMatching.match(
            sessions: sessions, activities: StrengthActivityMatching.removingDuplicates(input.strengthRecordings)
        ).bySession

        var usedIDs = Set(sessions.flatMap { $0.entries.map(\.exerciseID) })
        usedIDs.formUnion(input.routines.flatMap(\.exerciseIDs))
        usedIDs.formUnion(input.settings.keys)
        usedIDs.formUnion(input.profile?.goal?.priorityLifts ?? [])

        return ContextPack(
            about: about,
            generatedAt: now,
            app: .init(name: "Overreach", version: input.appVersion),
            period: .init(from: period.lowerBound.description, to: period.upperBound.description),
            athlete: athlete(input.profile, routines: input.routines, today: CalendarDay(now, calendar: calendar), name: name),
            catalog: input.exercises.map(\.name).sorted(),
            exercises: usedIDs.compactMap { byID[$0] }
                .sorted { $0.name < $1.name }
                .map { exerciseInfo($0, settings: input.settings[$0.id]) },
            routines: input.routines.map { routine in
                .init(id: routine.id.uuidString, name: routine.name, focus: routine.focus?.rawValue,
                      exercises: routine.exerciseIDs.map(name),
                      prescriptions: routine.prescriptions.isEmpty ? nil : routine.prescriptions.map { item in
                          .init(exercise: name(item.exerciseID), scheme: scheme(item.scheme))
                      })
            },
            sessions: sessions.map { session in
                var shared = self.session(from: session, name: name, calendar: calendar)
                shared.watch = watchBySession[session.id].map(watch)
                return shared
            },
            exerciseTrends: trends(input, sessions: sessions, byID: byID),
            checkIns: input.checkIns.sorted { $0.day < $1.day }.map { checkIn in
                .init(date: checkIn.day.description, isSick: checkIn.isSick, energy: checkIn.energy,
                      soreness: checkIn.soreness, note: checkIn.note)
            },
            dailyMetrics: input.dailyMetrics.sorted { $0.day < $1.day }.map(metrics),
            runs: input.runs.sorted { $0.startedAt < $1.startedAt }.map { run(from: $0, calendar: calendar) },
            imports: [.init(format: PlanMessage.formatName, version: PlanMessage.currentVersion,
                            reference: PlanMessage.referenceURL, schema: PlanMessage.schemaURL)]
        )
    }

    // MARK: - Parts

    private static func athlete(
        _ profile: AthleteProfile?, routines: [Routine], today: CalendarDay, name: (UUID) -> String
    ) -> ContextPack.Athlete {
        let routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        guard let profile else { return .init(declaredBlocks: []) }
        return .init(
            sex: profile.sex?.rawValue,
            birthYear: profile.birthYear,
            bodyMassKg: rounded(profile.bodyMassKg),
            maxHeartRate: rounded(profile.maxHeartRate),
            restingHeartRate: rounded(profile.restingHeartRate),
            cycleTracking: profile.cycleTracking == .off ? nil : profile.cycleTracking.rawValue,
            goal: profile.goal.map { goal in
                let schedule = goal.kind == .hybrid ? goal.scheduledRuns.sorted { $0.day < $1.day } : []
                return .init(
                    kind: goal.kind.rawValue, targetDate: goal.targetDate?.description,
                    priorityLifts: goal.priorityLifts.map(name),
                    running: goal.kind == .hybrid ? goal.running.map {
                        .init(distanceMeters: $0.distanceMeters, targetSeconds: $0.targetSeconds,
                              aimsForPainFree: $0.aimsForPainFree)
                    } : nil,
                    nextRun: schedule.first { $0.day >= today && $0.completion == nil }.map(runningEntry),
                    runningSchedule: schedule.isEmpty ? nil : schedule.map(runningEntry)
                )
            },
            declaredBlocks: profile.declaredBlocks.map { block in
                let names = block.routineIDs.compactMap { routineNames[$0] }
                return .init(focus: block.focus.rawValue, start: block.start.description,
                             plannedWeeks: block.plannedWeeks, name: block.name, routines: names.isEmpty ? nil : names,
                             sessionsPerWeek: block.sessionsPerWeek)
            }
        )
    }

    private static func runningEntry(_ entry: PlannedRun) -> ContextPack.NextRun {
        ContextPack.NextRun(id: entry.id, day: entry.day.description, purpose: entry.purpose.rawValue,
                            durationMinutes: entry.durationMinutes, distanceMeters: entry.distanceMeters,
                            completed: entry.completion != nil)
    }

    private static func exerciseInfo(_ exercise: Exercise, settings: ProgressionSettings?) -> ContextPack.ExerciseInfo {
        .init(
            name: exercise.name,
            equipment: exercise.equipment.rawValue,
            primaryMuscles: exercise.primaryMuscles.map(\.rawValue).sorted(),
            secondaryMuscles: exercise.secondaryMuscles.isEmpty ? nil : exercise.secondaryMuscles.map(\.rawValue).sorted(),
            isCustom: exercise.isCustom ? true : nil,
            progression: settings.map { settings in
                .init(focus: settings.focus?.rawValue, scheme: scheme(settings.scheme),
                      incrementKg: settings.incrementKg, isMainLift: settings.isMainLift)
            }
        )
    }

    static func scheme(_ scheme: ProgressionScheme) -> ContextPack.Scheme {
        switch scheme {
        case let .doubleProgression(sets, minReps, maxReps, rpe):
            .init(type: "doubleProgression", sets: sets, minReps: minReps, maxReps: maxReps, targetRPE: rpe)
        case let .linearLoad(sets, reps, rpe):
            .init(type: "linearLoad", sets: sets, reps: reps, targetRPE: rpe)
        case let .repCycle(sets, blocks, rpe):
            .init(type: "repCycle", sets: sets, repBlocks: blocks, targetRPE: rpe)
        case let .rpeBased(sets, reps, rpe):
            .init(type: "rpeBased", sets: sets, reps: reps, targetRPE: rpe)
        }
    }

    private static func watch(_ recording: RecordedStrengthActivity) -> ContextPack.Watch {
        .init(
            source: recording.source.rawValue,
            averageHeartRate: recording.averageHeartRate.map { rounded($0, places: 0) },
            maxHeartRate: recording.maxHeartRate.map { rounded($0, places: 0) },
            trainingLoad: recording.trainingLoad.map { rounded($0, places: 1) },
            aerobicTrainingEffect: recording.aerobicTrainingEffect.map { rounded($0, places: 1) },
            anaerobicTrainingEffect: recording.anaerobicTrainingEffect.map { rounded($0, places: 1) }
        )
    }

    private static func session(
        from session: StrengthSession, name: (UUID) -> String, calendar: Calendar
    ) -> ContextPack.Session {
        .init(
            id: session.id.uuidString,
            date: CalendarDay(session.startedAt, calendar: calendar).description,
            startedAt: session.startedAt,
            durationSeconds: session.endedAt.map { rounded($0.timeIntervalSince(session.startedAt), places: 0) },
            name: session.name,
            focus: session.focus?.rawValue,
            source: session.source.rawValue,
            sessionRPE: session.sessionRPE,
            notes: session.notes,
            exercises: session.entries.map { entry in
                .init(exercise: name(entry.exerciseID), notes: entry.notes, sets: entry.sets.map { set in
                    .init(kind: set.kind == .working ? nil : set.kind.rawValue, weightKg: set.weightKg, reps: set.reps,
                          rpe: set.rpe, durationSeconds: set.durationSeconds, distanceMeters: set.distanceMeters)
                }, countsForProgression: entry.countsForProgression ? nil : false)
            }
        )
    }

    private static func trends(
        _ input: ContextInput, sessions: [StrengthSession], byID: [UUID: Exercise]
    ) -> [ContextPack.ExerciseTrend] {
        let allSessions = (input.earlierSessions + sessions).sorted { $0.startedAt < $1.startedAt }
        var seen = Set<UUID>()
        let ids = sessions.flatMap { $0.entries.map(\.exerciseID) }.filter { seen.insert($0).inserted }
        return ids.compactMap { id -> ContextPack.ExerciseTrend? in
            guard let exercise = byID[id] else { return nil }
            let inPeriod = ExerciseExposure.history(of: id, in: sessions)
            let settings = input.settings[id] ?? ProgressionSettings(for: exercise)
            let status = StallDetection.status(history: ExerciseExposure.history(of: id, in: allSessions), settings: settings)
            let lastWeight = inPeriod.last?.workingWeightKg ?? 0
            return .init(
                exercise: exercise.name,
                exposures: inPeriod.count,
                status: statusName(status),
                lastWorkingWeightKg: lastWeight > 0 ? lastWeight : nil,
                estimatedOneRepMaxKg: inPeriod.compactMap { exposure in
                    exposure.bestEstimatedOneRepMax.map {
                        .init(date: CalendarDay(exposure.date).description, kg: rounded($0, places: 1))
                    }
                }
            )
        }
        .sorted { $0.exercise < $1.exercise }
    }

    private static func statusName(_ status: ExerciseStatus) -> String {
        switch status {
        case .notEnoughData: "notEnoughData"
        case .progressing: "progressing"
        case .holding: "holding"
        case .stalled: "stalled"
        }
    }

    private static func metrics(_ day: DailyMetrics) -> ContextPack.Metrics {
        .init(
            date: day.day.description,
            source: day.sources.map(\.rawValue).sorted().joined(separator: ","),
            hrvMs: rounded(day.hrvNightlyAverageMs),
            hrvMetric: day.hrvMetric?.rawValue,
            hrvBaselineLowMs: rounded(day.hrvBaselineLowMs),
            hrvBaselineHighMs: rounded(day.hrvBaselineHighMs),
            restingHeartRate: rounded(day.restingHeartRate),
            sleepSeconds: rounded(day.sleepSeconds, places: 0),
            deepSleepSeconds: rounded(day.deepSleepSeconds, places: 0),
            remSleepSeconds: rounded(day.remSleepSeconds, places: 0),
            sleepScore: rounded(day.sleepScore),
            bodyBatteryHigh: rounded(day.bodyBatteryHigh),
            bodyBatteryLow: rounded(day.bodyBatteryLow),
            averageStress: rounded(day.averageStress),
            steps: day.steps,
            vo2Max: rounded(day.vo2Max),
            trainingReadiness: rounded(day.trainingReadiness),
            acuteLoad: rounded(day.acuteLoad),
            recoveryTimeHours: rounded(day.recoveryTimeHours)
        )
    }

    private static func run(from run: RunActivity, calendar: Calendar) -> ContextPack.Run {
        .init(
            date: CalendarDay(run.startedAt, calendar: calendar).description,
            startedAt: run.startedAt,
            name: run.name,
            source: run.source.rawValue,
            durationSeconds: rounded(run.durationSeconds, places: 0),
            distanceMeters: rounded(run.distanceMeters, places: 0),
            paceSecondsPerKm: rounded(run.paceSecondsPerKm, places: 0),
            averageHeartRate: rounded(run.averageHeartRate),
            maxHeartRate: rounded(run.maxHeartRate),
            elevationGainMeters: rounded(run.elevationGainMeters),
            trainingLoad: rounded(run.trainingLoad),
            aerobicTrainingEffect: rounded(run.aerobicTrainingEffect),
            anaerobicTrainingEffect: rounded(run.anaerobicTrainingEffect)
        )
    }

    // MARK: - Helpers

    static func rounded(_ value: Double, places: Int = 1) -> Double {
        let factor = pow(10, Double(places))
        return (value * factor).rounded() / factor
    }

    static func rounded(_ value: Double?, places: Int = 1) -> Double? {
        value.map { rounded($0, places: places) }
    }
}
