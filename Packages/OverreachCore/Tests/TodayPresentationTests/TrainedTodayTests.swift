import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

/// Once the athlete has trained today, Today stops recommending more training unless the plan has another session.
@MainActor
@Suite("Today after training")
struct TrainedTodayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    /// Mid-afternoon, so a morning session has finished.
    private let now = Date(timeIntervalSince1970: 1_795_000_000 + 12 * 3_600)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private var morning: Date { calendar.startOfDay(for: now).addingTimeInterval(8 * 3_600) }
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)

    private var lift: StrengthSession {
        StrengthSession(
            name: "Lower", startedAt: morning, endedAt: morning.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 100, reps: 5, rpe: 8)])]
        )
    }

    private var run: RunActivity {
        RunActivity(id: "r1", source: .appleHealth, startedAt: morning, durationSeconds: 1_800, distanceMeters: 5_000)
    }

    private func model(sessions: [StrengthSession] = [], runs: [RunActivity] = []) async -> TodayModel {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let model = TodayModel(
            sources: [RestedSource(day: today, runs: runs)], workouts: store, exercises: store,
            calendar: calendar, format: format
        )
        await model.load(now: now)
        return model
    }

    @Test func aLiftTodayMeansNoSecondRecommendation() async {
        let model = await model(sessions: [lift])
        #expect(model.readinessLevel == .green)
        #expect(model.nextAction == .trainedToday)
        #expect(model.heroTitle == "You've trained today. Recovery is part of the plan.")
        #expect(model.primaryActionTitle() == "Log another workout")
    }

    @Test func aRunTodayMeansNoSecondRecommendation() async {
        let model = await model(runs: [run])
        #expect(model.nextAction == .trainedToday)
    }

    @Test func noTrainingTodayKeepsTheUsualAdvice() async {
        let model = await model()
        #expect(model.nextAction != .trainedToday)
        #expect(model.heroTitle == "Train as planned.")
    }

    @Test func aSessionFromYesterdayDoesNotCount() async {
        var yesterday = lift
        yesterday.startedAt = morning.addingTimeInterval(-86_400)
        yesterday.endedAt = morning.addingTimeInterval(-86_400 + 3_600)
        let model = await model(sessions: [yesterday])
        #expect(model.nextAction != .trainedToday)
    }

    @Test func heavyLegsYesterdayHoldBackAnUnplannedRun() async throws {
        var legs = lift
        legs.startedAt = morning.addingTimeInterval(-86_400)
        legs.endedAt = morning.addingTimeInterval(-86_400 + 3_600)
        legs.entries = [ExerciseEntry(exerciseID: squat.id, sets: Array(
            repeating: WorkoutSet(weightKg: 100, reps: 5, rpe: 7), count: 8
        ))]
        let model = await model(sessions: [legs])
        let option = try #require(model.runningOption)
        #expect(!option.isOptional)
        #expect(option.advice == "Leave the run for another day, or keep to a walk.")
        #expect(option.context == "You trained your legs hard yesterday. An extra run now adds load without a plan behind it.")
    }

    @Test func noLegsMeansNoHoldBack() async {
        let model = await model()
        #expect(model.runningOption?.advice != "Leave the run for another day, or keep to a walk.")
    }
}

private struct RestedSource: MetricsSource {
    let kind = DataSourceKind.appleHealth
    let day: CalendarDay
    let runs: [RunActivity]

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        var metrics = DailyMetrics(day: day, sources: [.appleHealth])
        metrics.sleepSeconds = 8 * 3_600
        return [metrics]
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runs }
}
