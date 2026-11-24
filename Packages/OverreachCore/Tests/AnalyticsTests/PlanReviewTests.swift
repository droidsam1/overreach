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

    @Test func blockProgressCountsOnlyCompletedRoutineSessionsWithinEachBlock() {
        var next = block
        next.start = day(14)
        next.sessionsPerWeek = 2
        var future = block
        future.start = day(56)

        var first = session(on: 2)
        first.endedAt = first.startedAt.addingTimeInterval(3600)
        var second = session(on: 14)
        second.endedAt = second.startedAt.addingTimeInterval(3600)
        var laterToday = session(on: 15)
        laterToday.endedAt = laterToday.startedAt.addingTimeInterval(3600)
        var unrelated = session(on: 1, Routine(name: "Other"))
        unrelated.endedAt = unrelated.startedAt.addingTimeInterval(3600)

        let progress = PlanReviewer.blockProgress(
            blocks: [block, next, future], sessions: [first, second, session(on: 8), laterToday, unrelated],
            now: day(15).startDate(in: calendar), calendar: calendar
        )

        #expect(progress.map { $0.block.start } == [day(14), start])
        #expect(progress.first?.weeks.map(\.done) == [1])
        #expect(progress.first?.weeks.map(\.planned) == [2])
        #expect(progress.first?.weeks.last?.isCurrent == true)
        #expect(progress.last?.weeks.map(\.done) == [1, 0])
        #expect(progress.last?.weeks.map(\.planned) == [3, 3])
        #expect(progress.last?.weeks.last?.isCurrent == false)
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

    // MARK: Daily recovery

    private func recovery(
        _ readiness: Readiness?, due: Bool = true, sessions: [StrengthSession] = [], checkIns: [CheckIn] = [],
        today: Int = 4
    ) -> PlanReview? {
        PlanReviewer.review(
            blocks: [block], sessions: sessions, checkIns: checkIns, today: day(today), readiness: readiness,
            sessionDue: due, calendar: calendar
        )
    }

    @Test func recoveryLightMapsToTheActionTodayShows() {
        #expect(DailyRecoveryAction(Readiness(level: .amber)) == .easier)
        #expect(DailyRecoveryAction(Readiness(level: .red)) == .recoveryDay)
        #expect(DailyRecoveryAction(Readiness(level: .amber, reasons: [.exerciseWarningSigns])) == .skip)
        #expect(DailyRecoveryAction(Readiness(level: .red, reasons: [.markedSick])) == .skip)
        #expect(DailyRecoveryAction(Readiness(level: .green)) == nil)
        #expect(DailyRecoveryAction(Readiness(level: .unknown, reasons: [.missingData])) == nil)
    }

    @Test func aLowerLightProposesLessForTodaysSessionOnly() throws {
        let amber = try #require(recovery(Readiness(level: .amber, reasons: [.hrvBelowBaseline(nights: 3)])))
        #expect(amber.adjustments == [.adaptToday(.easier)])
        #expect(amber.adjustments.first?.evidence == ReadinessEvidence.hrv)
        #expect(amber.adjustments.first?.changesThePlan == false)
        #expect(try #require(recovery(Readiness(level: .red))).adjustments == [.adaptToday(.recoveryDay)])
        let warning = Readiness(level: .red, reasons: [.exerciseWarningSigns])
        let skip = try #require(recovery(warning))
        #expect(skip.adjustments == [.adaptToday(.skip)])
        #expect(skip.adjustments.first?.evidence == ReadinessEvidence.reportedSymptoms)
    }

    @Test func normalUnavailableOrMissingReadingsProposeNothing() throws {
        #expect(try #require(recovery(Readiness(level: .green))).adjustments.isEmpty)
        #expect(try #require(recovery(Readiness(level: .unknown, reasons: [.missingData]))).adjustments.isEmpty)
        #expect(try #require(recovery(nil)).adjustments.isEmpty)
    }

    @Test func noSessionDueTodayOrNoRunningBlockProposesNothing() throws {
        #expect(try #require(recovery(Readiness(level: .red), due: false)).adjustments.isEmpty)
        let ended = PlanReviewer.review(
            blocks: [block], sessions: [], today: day(90), readiness: Readiness(level: .red), sessionDue: true,
            calendar: calendar
        )
        #expect(ended == nil)
        #expect(PlanReviewer.review(
            blocks: [], sessions: [], today: day(4), readiness: Readiness(level: .red), sessionDue: true,
            calendar: calendar
        ) == nil)
    }

    @Test func anIllnessStaysTheOnlyAdviceAndABreakKeepsItsOwn() throws {
        let ill = CheckIn(day: day(4), isSick: true)
        let sick = try #require(recovery(Readiness(level: .red, reasons: [.markedSick]), checkIns: [ill]))
        #expect(sick.adjustments == [.restWhileIll])
        let afterBreak = try #require(recovery(Readiness(level: .amber), sessions: [session(on: 0)], today: 20))
        #expect(afterBreak.adjustments == [.adaptToday(.easier), .easeBackIn(daysOff: 20)])
    }

    @Test func aRecoveryObservationLeavesTheBlockAndItsTargetsIntact() throws {
        let review = try #require(recovery(Readiness(level: .red)))
        #expect(review.block == block)
        #expect(review.weeks.map(\.planned) == [3])
        #expect(PlanReviewer.applying(.adaptToday(.recoveryDay), to: block, in: [block]) == [block])
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
