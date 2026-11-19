import Analytics
import Domain
import Foundation
import Testing

@Suite("Plan schedule")
struct PlanScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private let upperA = Routine(name: "Upper A")
    private let lowerA = Routine(name: "Lower A")
    private let fullBody = Routine(name: "Full body")
    private let start = CalendarDay(year: 2027, month: 1, day: 4)  // a Monday

    private func strength(weeks: Int? = 6, routines: [Routine]? = nil, from day: CalendarDay? = nil) -> TrainingBlock {
        TrainingBlock(
            focus: .strength, start: day ?? start, plannedWeeks: weeks, isDeclared: true, name: "Strength",
            routineIDs: (routines ?? [upperA, lowerA]).map(\.id)
        )
    }

    private func session(_ routine: Routine?, on day: CalendarDay) -> StrengthSession {
        StrengthSession(
            name: routine?.name ?? "Free", startedAt: day.startDate(in: calendar).addingTimeInterval(18 * 3_600),
            routineID: routine?.id
        )
    }

    private func next(
        _ blocks: [TrainingBlock], sessions: [StrengthSession] = [], today: CalendarDay
    ) -> PlannedSession? {
        PlanSchedule.next(
            blocks: blocks, routines: [upperA, lowerA, fullBody], sessions: sessions, today: today, calendar: calendar
        )
    }

    @Test func startsWithTheFirstRoutineOfTheBlock() throws {
        let planned = try #require(next([strength()], today: start))
        #expect(planned.routine == upperA)
        #expect(planned.week == 1)
        #expect(planned.totalWeeks == 6)
    }

    @Test func rotatesAfterTheLastSessionOfTheBlockAndDoesNotSkipMissedDays() throws {
        let tenth = start.adding(days: 10, calendar: calendar)
        let sessions = [
            session(upperA, on: start),
            session(nil, on: start.adding(days: 1, calendar: calendar)),  // a free session does not move the plan
            session(lowerA, on: start.adding(days: 2, calendar: calendar)),
            session(upperA, on: start.adding(days: 4, calendar: calendar)),
        ]
        let planned = try #require(next([strength()], sessions: sessions, today: tenth))
        #expect(planned.routine == lowerA)
        #expect(planned.week == 2)
    }

    @Test func sessionsBeforeTheBlockDoNotCount() throws {
        let before = session(upperA, on: start.adding(days: -2, calendar: calendar))
        #expect(try #require(next([strength()], sessions: [before], today: start)).routine == upperA)
    }

    @Test func nothingIsPlannedBeforeTheFirstBlockOrAfterTheLast() {
        #expect(next([strength()], today: start.adding(days: -1, calendar: calendar)) == nil)
        #expect(next([strength(weeks: 6)], today: start.adding(days: 42, calendar: calendar)) == nil)
        #expect(next([strength(weeks: 6)], today: start.adding(days: 41, calendar: calendar))?.week == 6)
    }

    @Test func theNextBlockTakesOverOnItsFirstDay() throws {
        let hypertrophyStart = start.adding(days: 42, calendar: calendar)
        let hypertrophy = TrainingBlock(
            focus: .hypertrophy, start: hypertrophyStart, plannedWeeks: 4, isDeclared: true,
            routineIDs: [fullBody.id]
        )
        let planned = try #require(next([hypertrophy, strength()], today: hypertrophyStart))
        #expect(planned.routine == fullBody)
        #expect(planned.block.focus == .hypertrophy)
        #expect(planned.week == 1)
    }

    @Test func openEndedBlocksRunUntilTheNextOne() throws {
        let planned = try #require(next([strength(weeks: nil)], today: start.adding(days: 100, calendar: calendar)))
        #expect(planned.week == 15)
        #expect(planned.totalWeeks == nil)
    }

    @Test func blocksWithoutRoutinesOrInferredBlocksPlanNothing() {
        #expect(next([strength(routines: [])], today: start) == nil)
        let inferred = TrainingBlock(focus: .strength, start: start, isDeclared: false, routineIDs: [upperA.id])
        #expect(next([inferred], today: start) == nil)
        let deleted = TrainingBlock(focus: .strength, start: start, isDeclared: true, routineIDs: [UUID()])
        #expect(next([deleted], today: start) == nil)
    }
}
