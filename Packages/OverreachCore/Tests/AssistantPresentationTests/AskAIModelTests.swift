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

        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        let preview = try #require(model.previewMessage)
        model.confirmPreview()
        let message = try #require(model.message)
        #expect(preview == message)
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
        model.confirmPreview()
        let linked = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(linked.runs.isEmpty)
        #expect(linked.sessions.first?.watch == nil)
        #expect(linked.today == nil)
        for group in ContextMetricGroup.allCases { model.setMetric(group, included: true) }
        model.confirmPreview()
        let withHealth = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(withHealth.sessions.first?.watch?.averageHeartRate == 125)
        for group in ContextMetricGroup.allCases { model.setMetric(group, included: false) }
        model.confirmPreview()
        let withoutHealth = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(withoutHealth.sessions.first?.watch == nil)

        choices = ActivityMatchChoices(runs: [runPair: .separate], strength: [liftPair: .separate])
        await model.prepare()
        model.confirmPreview()
        let separated = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(separated.runs.map(\.source) == ["appleHealth"])
        #expect(separated.sessions.first?.watch == nil)
        #expect(separated.sessions.first?.exercises.first?.sets.count == 1)

        await model.setPeriod(.sixMonths)
        model.confirmPreview()
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
        model.setAvailability("Mondays and Fridays, 45 minutes")
        #expect(try #require(model.previewMessage).contains(PlanMessage.jsonSchema))
        #expect(try #require(model.previewMessage).contains("Mondays and Fridays, 45 minutes"))
        #expect(try #require(model.previewMessage).hasSuffix("Help me plan my next training block."))

        model.setRequest(nil)
        #expect(try #require(model.previewMessage).hasSuffix("```"))
    }

    @Test func aFailureIsExplainedAndNothingIsOffered() async {
        let model = makeModel(failing: true)
        await model.prepare()
        model.confirmPreview()

        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        #expect(model.errorMessage == "Could not prepare your data. Try again.")
    }

    @Test func timingFromMergedSleepWindowsRequiresHealthOptIn() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let now = self.now
        let today = CalendarDay(now, calendar: calendar)
        let nights = (1...8).map { daysAgo -> DailyMetrics in
            let day = today.adding(days: -daysAgo, calendar: calendar)
            let midnight = day.startDate(in: calendar)
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.sleepSeconds = 8 * 3_600
            metrics.sleepStart = midnight.addingTimeInterval(-3_600)
            metrics.sleepEnd = midnight.addingTimeInterval(7 * 3_600)
            return metrics
        }
        let store = TestStore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            sources: [ExportSleepSource(nights: nights)], clock: { now }, calendar: calendar, directory: directory
        )
        await model.prepare()
        model.confirmPreview()
        let withoutHealth = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(withoutHealth.sleepTrainingTiming == nil)
        for group in ContextMetricGroup.allCases { model.setMetric(group, included: true) }
        model.confirmPreview()
        let withHealth = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        let timing = try #require(withHealth.sleepTrainingTiming)
        #expect(withHealth.version == 1)
        #expect(timing.windowDays == 28)
        #expect(timing.nights == 8)
        #expect(timing.usualBedtimeMinutesAfterMidnight.map { abs($0 - 1_380) < 0.01 } == true)
        #expect(timing.usualWakeMinutesAfterMidnight.map { abs($0 - 420) < 0.01 } == true)
        #expect(timing.usualTrainingStartMinutesAfterMidnight == nil)
        for group in ContextMetricGroup.allCases { model.setMetric(group, included: false) }
        model.confirmPreview()
        let redacted = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(redacted.sleepTrainingTiming == nil)
    }

    @Test func sharesOnlySelectedMetricsAndRequiresConfirmationAfterEdits() async throws {
        let now = self.now
        let calendar = Calendar(identifier: .gregorian)
        let today = CalendarDay(now, calendar: calendar)
        let older = today.adding(days: -70, calendar: calendar)
        let walk = WalkBout(
            start: older.startDate(in: calendar), durationSeconds: 600, distanceMeters: 800,
            averageHeartRate: 105, source: .garmin
        )
        let watch = RecordedStrengthActivity(
            id: "watch-recording", source: .garmin, startedAt: walk.end,
            durationSeconds: 1_800, averageHeartRate: 120, trainingLoad: 45
        )
        let store = TestStore()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AskAIModel(
            workouts: store, exercises: store, progression: store, profiles: store, routines: store,
            sources: [ExportSleepSource(nights: [garminMetrics(on: older)])],
            recordedStrength: ExportStrengthSource(watch), activity: [ExportWalkSource(day: older, walk: walk)],
            clock: { now }, calendar: calendar, directory: directory
        )

        await model.prepare()
        model.setMetric(.heart, included: true)
        model.setMetric(.movement, included: true)
        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        model.confirmPreview()
        let selected = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(selected.dailyMetrics.first?.hrvMs == 47)
        #expect(selected.dailyMetrics.first?.sleepSeconds == nil)
        #expect(selected.dailyMetrics.first?.acuteLoad == nil)
        #expect(selected.walks?.first?.averageHeartRate == 105)
        #expect(selected.strengthRecordings?.first?.watch?.averageHeartRate == 120)
        #expect(selected.strengthRecordings?.first?.watch?.trainingLoad == nil)

        model.setMetric(.heart, included: false)
        #expect(model.message == nil)
        #expect(model.fileURL == nil)
        model.confirmPreview()
        let movement = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(movement.walks?.first?.distanceMeters == 800)
        #expect(movement.walks?.first?.averageHeartRate == nil)
        #expect(movement.strengthRecordings == nil)

        await model.setPeriod(.fourWeeks)
        #expect(model.message == nil)
        model.confirmPreview()
        let recent = try ContextMessage.decode(Data(contentsOf: #require(model.fileURL)))
        #expect(recent.walks == nil)
    }

    private func garminMetrics(on day: CalendarDay) -> DailyMetrics {
        var metrics = DailyMetrics(day: day, sources: [.garmin])
        metrics.hrvRMSSDMs = 47
        metrics.sleepSeconds = 27_000
        metrics.acuteLoad = 321
        return metrics
    }

    @Test func optionsAreNamed() {
        let model = makeModel()
        #expect(model.periodOptions.map(\.value) == ContextPeriod.allCases)
        #expect(model.periodOptions.allSatisfy { !$0.name.isEmpty })
        #expect(model.requestOptions.count == StarterRequest.allCases.count)
    }
}

private struct ExportSleepSource: MetricsSource {
    let nights: [DailyMetrics]
    let kind: DataSourceKind = .garmin

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        nights.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
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

private struct ExportWalkSource: ActivitySource {
    let day: CalendarDay
    let walk: WalkBout

    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        range.contains(day) ? [DailyActivity(day: day, walks: [walk])] : []
    }
}
