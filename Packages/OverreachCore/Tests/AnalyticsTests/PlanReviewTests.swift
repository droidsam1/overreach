import Analytics
import Domain
import Foundation
import Testing

@Suite("Plan follow-up")
struct PlanReviewTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private let upper = Routine(name: "Upper")
    private let lower = Routine(name: "Lower")
    private let full = Routine(name: "Full body")
    private let start = CalendarDay(year: 2027, month: 1, day: 4)  // a Monday

    /// Three sessions a week planned through three routines, six weeks.
    private var block: TrainingBlock {
        TrainingBlock(
            focus: .strength, start: start, plannedWeeks: 6, isDeclared: true, name: "Strength",
            routineIDs: [upper.id, lower.id, full.id]
        )
    }

    private func day(_ offset: Int) -> CalendarDay { start.adding(days: offset, calendar: calendar) }

    private func session(on offset: Int, _ routine: Routine? = nil) -> StrengthSession {
        StrengthSession(
            name: "Session", startedAt: day(offset).startDate(in: calendar).addingTimeInterval(18 * 3_600),
            routineID: (routine ?? upper).id
        )
    }

    private func reviewed(
        _ sessions: [StrengthSession], today: Int, checkIns: [CheckIn] = [], blocks: [TrainingBlock]? = nil
    ) -> PlanReview? {
        PlanReviewer.review(
            blocks: blocks ?? [block], sessions: sessions, checkIns: checkIns, today: day(today), calendar: calendar
        )
    }

    // MARK: Planned against done

    @Test func countsPlannedAndDoneSessionsPerWeek() throws {
        let sessions = [
            session(on: 0), session(on: 2, lower), session(on: 4, full),  // week 1: all three
            session(on: 8), session(on: 10, lower),  // week 2: two of three
            session(on: 14),  // week 3, in progress
            StrengthSession(name: "Free", startedAt: day(15).startDate(in: calendar)),  // not from the plan
            session(on: -3),  // before the block
        ]
        let review = try #require(reviewed(sessions, today: 16))
        #expect(review.weeks.map(\.done) == [3, 2, 1])
        #expect(review.weeks.map(\.planned) == [3, 3, 3])
        #expect(review.currentWeek?.week == 3)
        #expect(review.currentWeek?.isCurrent == true)
        #expect(review.completedWeeksDone == 5)
        #expect(review.completedWeeksPlanned == 6)
        #expect(review.adjustments.isEmpty)  // 5 of 6 is on track
    }

    @Test func sessionsPerWeekCanDifferFromTheRoutines() throws {
        var twice = block
        twice.sessionsPerWeek = 2
        #expect(try #require(reviewed([], today: 3, blocks: [twice])).weeks.first?.planned == 2)
        let noRoutines = TrainingBlock(focus: .hypertrophy, start: start, plannedWeeks: 4, isDeclared: true)
        let anySession = StrengthSession(name: "Free", startedAt: day(1).startDate(in: calendar))
        let review = try #require(reviewed([anySession], today: 3, blocks: [noRoutines]))
        #expect(review.weeks.first?.planned == 1)
        #expect(review.weeks.first?.done == 1)  // without routines, any strength session counts
    }

    @Test func noRunningBlockNoReview() {
        #expect(reviewed([], today: -1) == nil)
        #expect(reviewed([], today: 42) == nil)
    }

    // MARK: Adjustments

    @Test func missedSessionsProposeFewerSessionsAndALongerBlock() throws {
        // Weeks 1–3: one session a week out of three; today is in week 4.
        let sessions = [session(on: 1), session(on: 8), session(on: 15)]
        let review = try #require(reviewed(sessions, today: 22))
        #expect(review.adjustments == [.fewerSessions(from: 3, perWeek: 1), .extendBlock(weeks: 2)])
        #expect(review.adjustments.map(\.evidence.key) == ["frequency-volume-equated", "plan-adherence"])
    }

    @Test func oneWeekIsNotEnoughToJudge() throws {
        let review = try #require(reviewed([session(on: 1)], today: 8))
        #expect(review.adjustments.isEmpty)
    }

    @Test func aBreakMeansEasingBackInNotChangingThePlan() throws {
        let sessions = [session(on: 0), session(on: 2, lower)]
        let review = try #require(reviewed(sessions, today: 20))
        #expect(review.adjustments == [.easeBackIn(daysOff: 18)])
        #expect(review.adjustments.first?.evidence == PlanEvidence.retraining)
        #expect(review.adjustments.first?.changesThePlan == false)
    }

    @Test func illnessComesFirst() throws {
        let sessions = [session(on: 1), session(on: 8), session(on: 15)]
        let ill = CheckIn(day: day(21), isSick: true)
        #expect(try #require(reviewed(sessions, today: 22, checkIns: [ill])).adjustments == [.restWhileIll])
        let longAgo = CheckIn(day: day(10), isSick: true)
        #expect(try #require(reviewed(sessions, today: 22, checkIns: [longAgo])).adjustments.first != .restWhileIll)
    }

    // MARK: Applying

    @Test func fewerSessionsChangesOnlyThatBlock() {
        let later = TrainingBlock(focus: .hypertrophy, start: day(42), plannedWeeks: 4, isDeclared: true)
        let result = PlanReviewer.applying(.fewerSessions(from: 3, perWeek: 2), to: block, in: [block, later])
        #expect(result[0].sessionsPerWeek == 2)
        #expect(result[0].plannedSessionsPerWeek == 2)
        #expect(result[1] == later)
    }

    @Test func extendingMovesTheLaterBlocks() {
        let earlier = TrainingBlock(focus: .mixed, start: day(-60), plannedWeeks: 8, isDeclared: true)
        let later = TrainingBlock(focus: .hypertrophy, start: day(42), plannedWeeks: 4, isDeclared: true)
        let inferred = TrainingBlock(focus: .endurance, start: day(50), isDeclared: false)
        let result = PlanReviewer.applying(.extendBlock(weeks: 2), to: block, in: [earlier, block, later, inferred])
        #expect(result[0] == earlier)
        #expect(result[1].plannedWeeks == 8)
        #expect(result[1].extendedWeeks == 2)
        let again = PlanReviewer.review(
            blocks: [result[1]], sessions: [session(on: 1), session(on: 8), session(on: 15)], today: day(22),
            calendar: calendar
        )
        #expect(again?.adjustments == [.fewerSessions(from: 3, perWeek: 1)])  // the extension is not offered twice
        #expect(result[2].start == day(56))
        #expect(result[3] == inferred)
        #expect(PlanReviewer.applying(.restWhileIll, to: block, in: [block]) == [block])
    }
}
