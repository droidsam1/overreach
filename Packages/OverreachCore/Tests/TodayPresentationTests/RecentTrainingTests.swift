import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

@MainActor
@Suite("Recent training and recovery")
struct RecentTrainingTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 20)

    private func madrid() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        return calendar
    }

    @Test func joinsRecoveryAndCompletedActivitiesWithoutCountingWatchCopies() async throws {
        let calendar = try madrid()
        let start = today.startDate(in: calendar)
        let now = start.addingTimeInterval(14 * 3_600)
        let yesterday = today.adding(days: -1, calendar: calendar)
        var metrics = DailyMetrics(day: today, sources: [.garmin])
        metrics.hrvNightlyAverageMs = 34
        metrics.hrvMetric = .rmssd
        metrics.restingHeartRate = 60
        metrics.sleepSeconds = 7.5 * 3_600
        var priorMetrics = DailyMetrics(day: yesterday, sources: [.garmin])
        priorMetrics.hrvNightlyAverageMs = 43
        priorMetrics.hrvMetric = .rmssd

        // The two copies begin on opposite sides of local midnight. The preferred record determines the day.
        let garminRun = RunActivity(
            id: "watch-run", source: .garmin, name: "Treadmill", startedAt: start.addingTimeInterval(-60),
            durationSeconds: 30 * 60, distanceMeters: 0
        )
        let healthCopy = RunActivity(
            id: "health-copy", source: .appleHealth, startedAt: start.addingTimeInterval(60),
            durationSeconds: 28 * 60, distanceMeters: 0
        )
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps, .glutes])
        let lift = StrengthSession(
            name: "Squat session", startedAt: start.addingTimeInterval(3_600), endedAt: start.addingTimeInterval(7_200),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(kind: .warmup), WorkoutSet(reps: 6)])]
        )
        let watchCopy = RecordedStrengthActivity(
            id: "watch-lift", source: .garmin, startedAt: lift.startedAt, durationSeconds: 3_600
        )
        let inProgress = StrengthSession(name: "Still training", startedAt: now.addingTimeInterval(-300))
        let store = TestStore(exercises: [squat], sessions: [inProgress, lift])
        let model = TodayModel(
            sources: [TimelineSource(kind: .garmin, metrics: [metrics, priorMetrics], runs: [garminRun]),
                      TimelineSource(kind: .appleHealth, runs: [healthCopy])],
            checkIns: TimelineCheckIns(records: [CheckIn(day: yesterday, energy: 4)]),
            workouts: store, exercises: store, recordedStrength: TimelineStrength(recordings: [watchCopy]),
            calendar: calendar, format: Format(locale: Locale(identifier: "en_US"))
        )

        await model.load(now: now)

        #expect(model.recentTrainingDays.map(\.id) == [today, yesterday])
        let latest = try #require(model.recentTrainingDays.first)
        #expect(latest.recovery == "HRV (RMSSD) 34 ms · Resting HR 60 bpm · Sleep 7.5 h")
        #expect(latest.workouts.count == 1)
        #expect(latest.workouts.first?.contains("Squat session · 60 min · Leg working sets 1") == true)
        #expect(latest.workouts.first?.contains("RPE") == false)
        let priorDay = try #require(model.recentTrainingDays.last)
        #expect(priorDay.recovery == "HRV (RMSSD) 43 ms · Energy 4/5")
        #expect(priorDay.workouts.count == 1)
        #expect(priorDay.workouts.first?.hasSuffix("Treadmill · 30 min") == true)
    }

    @Test func sourceFailureKeepsAvailableTraining() async throws {
        let calendar = try madrid()
        let now = today.startDate(in: calendar).addingTimeInterval(3_600)
        let run = RunActivity(id: "run", source: .garmin, startedAt: now.addingTimeInterval(-1_800),
                              durationSeconds: 1_800, distanceMeters: 5_000)
        let model = TodayModel(
            sources: [TimelineSource(kind: .appleHealth, fails: true), TimelineSource(kind: .garmin, runs: [run])],
            calendar: calendar
        )

        await model.load(now: now)

        #expect(model.recentTrainingDays.first?.workouts.count == 1)
        #expect(model.trainingTimelineNote == "Some recent workouts could not be loaded.")
    }

    @Test func recoveryWithoutRecordedExerciseRemainsVisible() async throws {
        let calendar = try madrid()
        var metrics = DailyMetrics(day: today, sources: [.appleHealth])
        metrics.sleepSeconds = 7 * 3_600
        let model = TodayModel(sources: [TimelineSource(kind: .appleHealth, metrics: [metrics])], calendar: calendar)
        await model.load(now: today.startDate(in: calendar))

        #expect(model.showsTrainingTimeline)
        #expect(model.recentTrainingDays.first?.workouts.isEmpty == true)
        #expect(model.trainingTimelineNote == "No completed workouts found in the last 7 days.")
    }
}

private struct TimelineSource: MetricsSource {
    struct ReadFailure: Error {}

    let kind: DataSourceKind
    var metrics: [DailyMetrics] = []
    var runs: [RunActivity] = []
    var fails = false

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { metrics }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        if fails { throw ReadFailure() }
        return runs.filter { (start...end).contains($0.startedAt) }
    }
}

private struct TimelineStrength: RecordedStrengthSource {
    let recordings: [RecordedStrengthActivity]

    func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] { recordings }
}

private struct TimelineCheckIns: CheckInRepository {
    let records: [CheckIn]

    func checkIn(for day: CalendarDay) async throws -> CheckIn? { records.first { $0.day == day } }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { records.filter { range.contains($0.day) } }
    func save(_ checkIn: CheckIn) async throws {}
}
