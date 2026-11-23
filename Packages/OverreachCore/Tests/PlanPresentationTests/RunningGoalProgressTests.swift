import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

@MainActor
@Suite("Running goal progress")
struct RunningGoalProgressTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func linkedRun(id: String = "watch", distance: Double = 5_000, duration: Double = 900) -> PlannedRun {
        let start = now.addingTimeInterval(-86_400)
        let activity = RunActivity(id: id, source: .garmin, startedAt: start, durationSeconds: duration,
                                   distanceMeters: distance)
        return PlannedRun(day: CalendarDay(start, calendar: calendar), purpose: .race,
                          completion: PlannedRunCompletion(activity))
    }

    private func model(entries: [PlannedRun], goal: RunningGoal) async throws -> (PlanModel, TestStore) {
        var trainingGoal = TrainingGoal(kind: .hybrid, running: goal)
        trainingGoal.setRunningSchedule(entries)
        let store = TestStore()
        try await store.save(AthleteProfile(goal: trainingGoal))
        let fixedNow = now
        let model = PlanModel(profiles: store, workouts: store, exercises: store, progression: store,
                              clock: { fixedNow }, calendar: calendar)
        await model.load()
        return (model, store)
    }

    @Test func usesTheSameMeasuredRunForDistanceTimeAndPain() async throws {
        let goal = RunningGoal(distanceMeters: 5_000, targetSeconds: 900, aimsForPainFree: true)
        let (model, store) = try await model(entries: [linkedRun()], goal: goal)
        let row = try #require(model.runningGoalProgress?.rows.first)
        #expect(row.summary == "5 km · 15:00")
        #expect(!row.meetsGoal)
        #expect(await model.saveRunningPain(row, during: false, after: nil))
        #expect(model.runningGoalProgress?.rows.first?.meetsGoal == false)
        #expect(await model.saveRunningPain(row, during: false, after: false))
        #expect(model.runningGoalProgress?.rows.first?.meetsGoal == true)

        let profile = try await store.profile()
        let backup = BackupDocument(createdAt: now, profile: profile)
        #expect(try BackupCodec.decode(BackupCodec.encode(backup)).profile == profile)

        #expect(await model.saveRunningPain(row, during: true, after: false))
        #expect(model.runningGoalProgress?.rows.first?.meetsGoal == false)
    }

    @Test func savesSeverityAndNextMorningStatusWithTheLinkedRun() async throws {
        let goal = RunningGoal(distanceMeters: 5_000, aimsForPainFree: true)
        let (model, store) = try await model(entries: [linkedRun()], goal: goal)
        let row = try #require(model.runningGoalProgress?.rows.first)
        #expect(await model.saveRunningPain(row, severityDuring: 2, severityAfter: 3, settledByMorning: true))
        let saved = try #require(try await store.profile().goal?.scheduledRuns.first?.completion)
        #expect(saved.severityDuring == 2 && saved.severityAfter == 3 && saved.settledByMorning == true)
        #expect(saved.painDuring == true && saved.painAfter == true)
        #expect(saved.painReport.isTolerated())
        #expect(model.runningGoalProgress?.rows.first?.painStatus == "Pain up to 3/10, settled by morning")
        #expect(model.runningGoalProgress?.rows.first?.meetsGoal == false)
    }

    @Test func aLongerRunWithOnlyATotalTimeDoesNotSupplyAnUnobservedSplit() throws {
        let goal = RunningGoal(distanceMeters: 5_000, targetSeconds: 900)
        let long = try #require(linkedRun(distance: 8_000, duration: 1_600).completion)
        let short = try #require(linkedRun(distance: 4_999, duration: 890).completion)
        #expect(!goal.isMet(by: long))
        #expect(!goal.isMet(by: short))
        #expect(RunningGoal(distanceMeters: 5_000).isMet(by: long))
    }

    @Test func anOlderLinkHasUnknownDistanceAndPain() throws {
        let legacy = #"{"activityID":"watch","source":"garmin","startedAt":0,"durationSeconds":900}"#
        let result = try JSONDecoder().decode(PlannedRunCompletion.self, from: Data(legacy.utf8))
        #expect(result.distanceMeters == nil)
        #expect(result.painDuring == nil)
        #expect(result.painAfter == nil)
        #expect(!RunningGoal(distanceMeters: 5_000).isMet(by: result))
    }

    @Test func savingAReportForAnUnlinkedRunLeavesTheScheduleAlone() async throws {
        let entry = linkedRun()
        let (model, store) = try await model(entries: [entry], goal: RunningGoal(distanceMeters: 5_000))
        let row = try #require(model.runningGoalProgress?.rows.first)
        #expect(await model.removeRunningEntry(entry.id))
        #expect(!(await model.saveRunningPain(row, during: false, after: false)))
        #expect(try await store.profile().goal?.scheduledRuns.isEmpty == true)
    }
}
