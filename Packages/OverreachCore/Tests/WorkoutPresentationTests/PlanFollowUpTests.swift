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
        #expect(!model.planChecks[0].readings.isEmpty)  // frequency: volume and frequency readings
        #expect(model.planChecks[1].readings.isEmpty)   // a heuristic with nothing curated
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

    // MARK: Daily recovery

    private func recoveryModel(
        _ readiness: Readiness?, sessionDays: [Int] = [0, 2], today: Int = 4, hasBlock: Bool = true
    ) async throws -> (RoutinesModel, TestStore) {
        let sessions = sessionDays.map { StrengthSession(name: "Upper", startedAt: date($0), routineID: upper.id) }
        let store = TestStore(exercises: [squat], sessions: sessions, routines: [upper, lower, full])
        var profile = AthleteProfile()
        profile.declaredBlocks = hasBlock ? [block] : []
        try await store.save(profile)
        let now = start.adding(days: today, calendar: calendar).startDate(in: calendar).addingTimeInterval(20 * 3_600)
        let model = RoutinesModel(
            routines: store, exercises: store, profiles: store, workouts: store, checkIns: CheckIns([]),
            readiness: { _, _ in readiness }, calendar: calendar, clock: { now }
        )
        await model.load()
        return (model, store)
    }

    @Test func aLowerLightExplainsWhyTodaysSessionShouldBeEasier() async throws {
        let amber = Readiness(level: .amber, reasons: [.hrvBelowBaseline(nights: 3), .hrvMayReflectCycle])
        let (model, store) = try await recoveryModel(amber)
        let check = try #require(model.planChecks.first)
        #expect(model.planChecks.count == 1)
        #expect(check.text == "Keep Lower easy today.")
        #expect(check.reason == "HRV below your usual range. (moderate evidence)")  // context reasons are left out
        #expect(check.actionTitle == nil)
        #expect(!check.readings.isEmpty)
        #expect(try await store.profile().declaredBlocks == [block])  // the plan stays as entered
        #expect(model.upNext?.title == "Lower")
    }

    @Test func aRedLightAndWarningSignsProposeARecoveryDayAndRest() async throws {
        let elevated = Readiness(level: .red, reasons: [.restingHeartRateElevated(bpmAboveBaseline: 8)])
        let (red, _) = try await recoveryModel(elevated)
        #expect(red.planChecks.first?.text
            == "Make Lower a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        #expect(red.planChecks.first?.reason == "Resting HR 8 bpm above your usual. (moderate evidence)")

        let (warning, _) = try await recoveryModel(Readiness(level: .red, reasons: [.exerciseWarningSigns]))
        #expect(warning.planChecks.first?.text == "Skip Lower today and reassess how you feel.")
        #expect(warning.planChecks.first?.reason == "Symptoms to discuss with a clinician (limited evidence)")
    }

    @Test func normalOrUnavailableReadingsAddNoProposal() async throws {
        for readiness in [Readiness(level: .green), Readiness(level: .unknown, reasons: [.missingData]), nil] {
            let (model, _) = try await recoveryModel(readiness)
            #expect(model.planChecks.isEmpty)
        }
    }

    @Test func noProposalWithoutAnActiveBlockOrAfterTrainingToday() async throws {
        let (noBlock, _) = try await recoveryModel(Readiness(level: .red), hasBlock: false)
        #expect(noBlock.planChecks.isEmpty)
        #expect(noBlock.upNext == nil)
        let (trained, _) = try await recoveryModel(Readiness(level: .red), sessionDays: [0, 2, 4], today: 4)
        #expect(trained.planChecks.isEmpty)
    }
}
