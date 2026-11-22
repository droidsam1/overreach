import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

@MainActor
@Suite("Plan overview")
struct PlanOverviewTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func model(goal: TrainingGoal? = nil) async throws -> (PlanModel, TestStore) {
        let store = TestStore(exercises: [], sessions: [])
        if let goal { try await store.save(AthleteProfile(goal: goal)) }
        let fixedNow = now
        let model = PlanModel(
            profiles: store, workouts: store, exercises: store, progression: store, routines: store,
            clock: { fixedNow }, calendar: calendar
        )
        await model.load()
        return (model, store)
    }

    @Test func theScheduleLeadsWithTheNextThreeDatedEntriesAndSaysWhenThereAreMore() async throws {
        let today = CalendarDay(now, calendar: calendar)
        let runs = (0..<4).map { PlannedRun(day: today.adding(days: $0), purpose: .easy) }
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: runs[0])
        let (model, store) = try await model(goal: goal)
        var profile = await store.profile()
        profile.goal?.setRunningSchedule(runs)
        try await store.save(profile)
        await model.load()

        #expect(model.nextSessionRows.map(\.id) == runs.prefix(3).map { .run($0.id) })
        #expect(model.hasMoreSessions)
    }

    @Test func anExplicitRestDayIsNotAnEmptySchedule() async throws {
        let today = CalendarDay(now, calendar: calendar)
        let rest = PlannedRun(day: today, purpose: .rest)
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: rest)
        let (model, _) = try await model(goal: goal)

        let rows = model.nextSessionRows
        #expect(rows.count == 1)
        #expect(rows.first?.isRest == true)
        let undated = try await self.model(goal: TrainingGoal(kind: .hybrid))
        #expect(undated.0.nextSessionRows.isEmpty)
    }

    @Test func theGoalSummaryNamesTheGoalAndItsTargetDate() async throws {
        let (model, _) = try await model(goal: TrainingGoal(kind: .strength))
        #expect(model.goalSummary == model.goalOptions.first { $0.value == .strength }?.name)
        await model.setHasTargetDate(true)
        #expect(model.goalSummary.contains(" · "))
    }

    @Test func importedBlockShowsProgressBeforeTheFirstWorkout() async throws {
        let (model, store) = try await model()
        let day = CalendarDay(now, calendar: calendar)
        let block = TrainingBlock(
            focus: .strength, start: day, plannedWeeks: 4, isDeclared: true, name: "Strength phase",
            routineIDs: [UUID(), UUID()]
        )
        try await store.save(AthleteProfile(declaredBlocks: [block]))
        await model.load()

        let row = try #require(model.importedPlanProgress.first)
        #expect(model.hasProgress)
        #expect(row.title.hasPrefix("Strength phase"))
        #expect(row.summary == "0 completed / 2 planned")
        #expect(row.weeks.map(\.title) == ["This week"])
        #expect(model.progressSummary == row.summary)
    }

    @Test func withoutHistoryProgressSaysSoInsteadOfShowingNothing() async throws {
        let (model, _) = try await model()
        #expect(!model.hasProgress)
        #expect(model.progressSummary == "No progress to show yet")
    }
}
