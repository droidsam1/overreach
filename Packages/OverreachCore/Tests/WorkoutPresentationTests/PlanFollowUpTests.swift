import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

private actor CheckIns: CheckInRepository {
    let stored: [CheckIn]
    init(_ stored: [CheckIn]) { self.stored = stored }
    func checkIn(for day: CalendarDay) async throws -> CheckIn? { stored.first { $0.day == day } }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] {
        stored.filter { range.contains($0.day) }
    }
    func save(_ checkIn: CheckIn) async throws {}
}

@MainActor
@Suite("Plan follow-up in Train")
struct PlanFollowUpTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let upper = Routine(name: "Upper")
    private let lower = Routine(name: "Lower")
    private let full = Routine(name: "Full body")
    private let start = CalendarDay(year: 2027, month: 1, day: 4)

    private var block: TrainingBlock {
        TrainingBlock(
            focus: .strength, start: start, plannedWeeks: 6, isDeclared: true, name: "Strength",
            routineIDs: [upper.id, lower.id, full.id]
        )
    }

    private func date(_ offset: Int) -> Date {
        start.adding(days: offset, calendar: calendar).startDate(in: calendar).addingTimeInterval(18 * 3_600)
    }

    private func model(
        sessionDays: [Int], today: Int, checkIns: [CheckIn] = []
    ) async throws -> (RoutinesModel, TestStore) {
        let sessions = sessionDays.map { StrengthSession(name: "Upper", startedAt: date($0), routineID: upper.id) }
        let store = TestStore(exercises: [squat], sessions: sessions, routines: [upper, lower, full])
        var profile = AthleteProfile()
        profile.declaredBlocks = [block]
        try await store.save(profile)
        let now = date(today)
        let model = RoutinesModel(
            routines: store, exercises: store, profiles: store, workouts: store, checkIns: CheckIns(checkIns),
            calendar: calendar, clock: { now }
        )
        await model.load()
        return (model, store)
    }

    @Test func showsThisWeeksSessions() async throws {
        let (model, _) = try await model(sessionDays: [0, 2, 4, 7], today: 9)
        #expect(model.upNext?.weekProgress == "This week: 1 of 3 sessions")
        #expect(model.planChecks.isEmpty)
    }

    @Test func proposesAndAppliesFewerSessionsAndALongerBlock() async throws {
        let (model, store) = try await model(sessionDays: [1, 8, 15], today: 22)
        #expect(model.planChecks.map(\.text) == [
            "Plan 1 sessions a week instead of 3.",
            "Add 2 weeks to “Strength” to make up for missed sessions.",
        ])
        #expect(model.planChecks[0].reason.hasSuffix("(strong evidence)"))
        #expect(model.planChecks[1].reason.hasSuffix("(coaching heuristic)"))
        #expect(model.planChecks.map(\.actionTitle) == ["Plan 1 a week", "Add 2 weeks"])

        // Extending once is enough: the same missed sessions are not offered again.
        await model.accept(model.planChecks[1])
        #expect(try await store.profile().declaredBlocks.first?.plannedWeeks == 8)
        #expect(model.planChecks.map(\.actionTitle) == ["Plan 1 a week"])

        await model.accept(model.planChecks[0])
        let saved = try #require(try await store.profile().declaredBlocks.first)
        #expect(saved.sessionsPerWeek == 1)
        #expect(model.upNext?.weekProgress == "This week: 0 of 1 sessions")
        #expect(model.planChecks.isEmpty)  // one a week is on track
    }

    @Test func adviceWithoutChangesAfterABreakOrAnIllness() async throws {
        let (afterBreak, _) = try await model(sessionDays: [0, 2], today: 20)
        #expect(afterBreak.planChecks.map(\.text) == [
            "18 days since your last session. Keep the plan and ease back in.",
        ])
        #expect(afterBreak.planChecks.first?.actionTitle == nil)

        let ill = CheckIn(day: start.adding(days: 22, calendar: calendar), isSick: true)
        let (whileIll, _) = try await model(sessionDays: [1, 8, 15], today: 22, checkIns: [ill])
        #expect(whileIll.planChecks.first?.reason.hasSuffix("(limited evidence)") == true)
        #expect(whileIll.planChecks.count == 1)
    }
}
