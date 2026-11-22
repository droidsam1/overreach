import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

@MainActor
@Suite("Today's completed summary")
struct TodayDoneTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_000_000 + 12 * 3_600)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private let press = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private var morning: Date { calendar.startOfDay(for: now).addingTimeInterval(8 * 3_600) }

    private func lift(weight: Double = 80, at start: Date, hasDuration: Bool = true) -> StrengthSession {
        StrengthSession(
            name: "Push A", startedAt: start, endedAt: hasDuration ? start.addingTimeInterval(3_600) : nil,
            entries: [ExerciseEntry(exerciseID: press.id, sets: [WorkoutSet(weightKg: weight, reps: 5, rpe: 8)])],
            source: hasDuration ? .app : .strongImport
        )
    }

    private func model(
        sessions: [StrengthSession] = [], runs: [RunActivity] = [], rest: Bool = false, goal: TrainingGoal? = nil
    ) async throws -> TodayModel {
        let store = TestStore(exercises: [press], sessions: sessions)
        try await store.save(AthleteProfile(goal: goal))
        let source = DoneSource(day: today, runs: runs)
        let model = TodayModel(
            sources: [source], checkIns: rest ? source : nil, profiles: store, workouts: store, exercises: store,
            calendar: calendar, format: format
        )
        await model.load(now: now)
        return model
    }

    @Test func strengthWithARecord() async throws {
        let previous = lift(weight: 70, at: morning.addingTimeInterval(-86_400))
        let model = try await model(sessions: [previous, lift(at: morning)])
        let done = try #require(model.doneToday)
        let session = try #require(done.sessions.first)

        #expect(done.title == "Push A completed")
        #expect(done.sessions.count == 1)
        #expect(session.duration == "60 min")
        #expect(session.sets == 1)
        #expect(session.volume == "400 kg")
        #expect(session.records.contains("Bench Press: Most volume ever in one session: 400 kg (before 350 kg)."))
    }

    @Test func firstLiftHasNoRecordAndUnknownDurationIsOmitted() async throws {
        let model = try await model(sessions: [lift(at: morning, hasDuration: false)])
        let session = try #require(model.doneToday?.sessions.first)

        #expect(session.records.isEmpty)
        #expect(session.duration == nil)
        #expect(session.sets == 1)
    }

    @Test func runningShowsDurationDistanceAndPace() async throws {
        let run = RunActivity(id: "run", source: .appleHealth, startedAt: morning,
                              durationSeconds: 1_800, distanceMeters: 5_000)
        let model = try await model(runs: [run])
        let done = try #require(model.doneToday)
        let session = try #require(done.sessions.first)

        #expect(done.title == "Run completed")
        #expect(session.duration == "30 min")
        #expect(session.distance == "5 km")
        #expect(session.pace == "6:00 /km")
        #expect(session.sets == nil)
        #expect(session.volume == nil)
        #expect(session.records.isEmpty)
    }

    @Test func loggedRestShowsTomorrowAndUndoClearsTheSummary() async throws {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let run = PlannedRun(day: tomorrow, purpose: .easy, distanceMeters: 5_000)
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: run)
        let model = try await model(rest: true, goal: goal)
        #expect(model.doneToday == nil)

        await model.logRest(now: now)
        let done = try #require(model.doneToday)

        #expect(done.title == "Rest logged")
        #expect(done.sessions.isEmpty)
        #expect(done.tomorrow.map(\.title) == ["Easy run"])
        #expect(done.tomorrow.first?.detail == "5 km")
        #expect(model.heroReason == "Tomorrow: Easy run · 5 km")
        await model.undoRest(now: now)
        #expect(model.doneToday == nil)
    }

    @Test func twoSessionsAreListedMostRecentFirst() async throws {
        let run = RunActivity(id: "run", source: .appleHealth, startedAt: morning.addingTimeInterval(3_600),
                              durationSeconds: 1_800, distanceMeters: 0)
        let model = try await model(sessions: [lift(at: morning)], runs: [run])
        let done = try #require(model.doneToday)

        #expect(done.title == "Run completed")
        #expect(done.sessions.map(\.title) == ["Run completed", "Push A completed"])
        #expect(done.sessions.first?.distance == nil)
        #expect(done.sessions.first?.pace == nil)
    }
}

private struct DoneSource: MetricsSource, CheckInRepository {
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
    func checkIn(for day: CalendarDay) async throws -> CheckIn? {
        day == self.day ? CheckIn(day: day, isSick: true) : nil
    }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { [] }
    func save(_ checkIn: CheckIn) async throws {}
}
