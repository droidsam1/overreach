import AIExchange
import AssistantPresentation
import Domain
import Fixtures
import Foundation
import Testing

@MainActor
@Suite("Ask AI screen")
struct AskAIModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(daysAgo: Double) -> StrengthSession {
        StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [WorkoutSet(weightKg: 60, reps: 10, rpe: 8)])]
        )
    }

    private func makeModel(failing: Bool = false) -> AskAIModel {
        let store = TestStore(exercises: [bench], sessions: [session(daysAgo: 3), session(daysAgo: 100)])
        let fixedNow = now
        let directory = failing
            ? URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
            : FileManager.default.temporaryDirectory
        return AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            clock: { fixedNow }, directory: directory
        )
    }

    @Test func preparesTheContextOfThePeriod() async throws {
        let model = makeModel()
        await model.prepare()

        let message = try #require(model.message)
        #expect(message.hasPrefix("Overreach training context (overreach.context v1)"))
        #expect(model.summary?.hasPrefix("1 sessions · 1 exercises · ") == true)
        #expect(model.errorMessage == nil)

        let url = try #require(model.fileURL)
        let pack = try ContextMessage.decode(Data(contentsOf: url))
        #expect(pack.sessions.count == 1)
        #expect(pack.exerciseTrends.first?.exercise == "Bench Press")
    }

    @Test func exportAppliesCurrentChoicesBeforeFilteringByPeriod() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = CalendarDay(now, calendar: calendar)
        let start = today.adding(days: -83, calendar: calendar).startDate(in: calendar)
        let garmin = RunActivity(id: "garmin", source: .garmin, startedAt: start.addingTimeInterval(-60),
                                 durationSeconds: 1_800, distanceMeters: 4_000)
        let health = RunActivity(id: "health", source: .appleHealth, startedAt: start.addingTimeInterval(60),
                                 durationSeconds: 1_800, distanceMeters: 4_000)
        let lift = session(daysAgo: 3)
        let watch = RecordedStrengthActivity(id: "lift", source: .garmin, startedAt: lift.startedAt,
                                             durationSeconds: 1_800, averageHeartRate: 125)
        let runPair = RunMatchPair(garminID: garmin.id, appleHealthID: health.id)
        let liftPair = StrengthMatchPair(sessionID: lift.id, recordingID: StrengthRecordingID(watch))
        let store = TestStore(exercises: [bench], sessions: [lift])
        let fixedNow = now
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var choices = ActivityMatchChoices(runs: [runPair: .linked], strength: [liftPair: .linked])
        let model = AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            sources: [ExportRunSource(garmin), ExportRunSource(health)], recordedStrength: ExportStrengthSource(watch),
            activityMatchChoices: { choices }, clock: { fixedNow }, calendar: calendar, directory: directory
        )

        await model.prepare()
        let linked = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(linked.runs.isEmpty)
        #expect(linked.sessions.first?.watch?.averageHeartRate == 125)

        choices = ActivityMatchChoices(runs: [runPair: .separate], strength: [liftPair: .separate])
        await model.prepare()
        let separated = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(separated.runs.map(\.source) == ["appleHealth"])
        #expect(separated.sessions.first?.watch == nil)
        #expect(separated.sessions.first?.exercises.first?.sets.count == 1)

        await model.setPeriod(.sixMonths)
        let extended = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(extended.runs.count == 2)
    }

    @Test func aLongerPeriodIncludesOlderSessions() async {
        let model = makeModel()
        await model.prepare()
        await model.setPeriod(.sixMonths)

        #expect(model.period == .sixMonths)
        #expect(model.summary?.hasPrefix("2 sessions") == true)
    }

    @Test func theFirstRequestGoesAfterTheDataAndCanBeRemoved() async throws {
        let model = makeModel()
        await model.prepare()

        model.setRequest(.nextBlock)
        #expect(try #require(model.message).hasSuffix("```\n\nHelp me plan my next training block."))

        model.setRequest(nil)
        #expect(try #require(model.message).hasSuffix("```"))
    }

    @Test func aFailureIsExplainedAndNothingIsOffered() async {
        let model = makeModel(failing: true)
        await model.prepare()

        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        #expect(model.errorMessage == "Could not prepare your data. Try again.")
    }

    @Test func optionsAreNamed() {
        let model = makeModel()
        #expect(model.periodOptions.map(\.value) == ContextPeriod.allCases)
        #expect(model.periodOptions.allSatisfy { !$0.name.isEmpty })
        #expect(model.requestOptions.count == StarterRequest.allCases.count)
    }
}

private struct ExportRunSource: MetricsSource {
    let run: RunActivity
    var kind: DataSourceKind { run.source }

    init(_ run: RunActivity) { self.run = run }

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        (start...end).contains(run.startedAt) ? [run] : []
    }
}

private struct ExportStrengthSource: RecordedStrengthSource {
    let recording: RecordedStrengthActivity

    init(_ recording: RecordedStrengthActivity) { self.recording = recording }

    func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] {
        (start...end).contains(recording.startedAt) ? [recording] : []
    }
}
