import Domain
import Foundation
import Testing
import TrainingServices

@Suite("Week progress")
struct WeekProgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()
    private let legs = UUID()
    private let push = UUID()

    /// Wednesday 18 November 2026 at noon: the week runs from Monday 16 to Sunday 22.
    private var now: Date { day(18).startDate(in: calendar).addingTimeInterval(12 * 3_600) }

    private func day(_ number: Int) -> CalendarDay {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: number)) ?? .distantPast
        return CalendarDay(date, calendar: calendar)
    }

    private func session(_ routine: UUID, on number: Int) -> StrengthSession {
        let start = day(number).startDate(in: calendar).addingTimeInterval(8 * 3_600)
        return StrengthSession(
            name: "Gym", startedAt: start, endedAt: start.addingTimeInterval(3_600), routineID: routine
        )
    }

    private func run(on number: Int) -> RunActivity {
        RunActivity(
            id: "run-\(number)", source: .garmin,
            startedAt: day(number).startDate(in: calendar).addingTimeInterval(7 * 3_600),
            durationSeconds: 1_800, distanceMeters: 5_000, averageHeartRate: 140
        )
    }

    private func progress(_ inputs: WeekProgress.Inputs) -> WeekProgress? {
        WeekProgress.make(inputs, now: now, calendar: calendar)
    }

    @Test func anEmptyWeekHasNoProgress() {
        #expect(progress(.init()) == nil)
    }

    @Test func listsSevenDaysFromMondayWithTodayMarked() throws {
        let week = try #require(progress(.init(restDays: [day(17)])))

        #expect(week.days.map(\.day) == (16...22).map(day))
        #expect(week.days.filter(\.isToday).map(\.day) == [day(18)])
    }

    @Test func aMixedWeekCountsRestLoggedAsACompletedDay() throws {
        let linked = PlannedRunCompletion(run(on: 17))
        let week = try #require(progress(.init(
            strength: [PlannedStrength(day: day(16), routineID: legs), PlannedStrength(day: day(20), routineID: push)],
            runs: [
                PlannedRun(day: day(17), purpose: .easy, durationMinutes: 30, completion: linked),
                PlannedRun(day: day(19), purpose: .tempo, durationMinutes: 20),
            ],
            sessions: [session(legs, on: 16)], recordedRuns: [run(on: 17)], restDays: [day(18)]
        )))

        #expect(week.sessionsDone == 2)
        #expect(week.sessionsPlanned == 4)
        #expect(week.strengthDone == 1 && week.strengthPlanned == 2)
        #expect(week.runsDone == 1 && week.runsPlanned == 2)
        #expect(week.days.map(\.done) == [.strength, .run, .restLogged, .nothing, .nothing, .nothing, .nothing])
        #expect(week.days[3].plannedRun && week.days[4].plannedStrength)
    }

    @Test func pastDaysWithoutTrainingAreRest() throws {
        let week = try #require(progress(.init(sessions: [session(legs, on: 17)])))

        #expect(week.days.map(\.done) == [.restLogged, .strength, .nothing, .nothing, .nothing, .nothing, .nothing])
    }

    @Test func aPlanWithABlockReportsItsWeek() throws {
        let block = TrainingBlock(focus: .strength, start: day(9), plannedWeeks: 4, isDeclared: true, name: nil)
        let week = try #require(progress(.init(blockWeek: (planned: 3, done: 1), currentBlock: block)))

        #expect(week.block?.focus == .strength)
        #expect(week.block?.week == 2 && week.block?.weeks == 4)
        #expect(week.sessionsPlanned == 3 && week.sessionsDone == 1)
    }

    @Test func withoutDatedEntriesTheBlockCountsItsOwnRoutinesThisWeek() throws {
        let block = TrainingBlock(
            focus: .strength, start: day(9), plannedWeeks: 4, isDeclared: true, routineIDs: [legs, push],
            sessionsPerWeek: 3
        )
        let other = UUID()
        let week = try #require(progress(.init(
            sessions: [session(legs, on: 16), session(other, on: 17), session(push, on: 12)], currentBlock: block
        )))

        #expect(week.sessionsPlanned == 3 && week.sessionsDone == 1)
    }

    @Test func aWeekCrossingADeloadMarksItsDaysWithoutMissingSessions() throws {
        let week = try #require(progress(.init(
            strength: [PlannedStrength(day: day(16), routineID: legs)], sessions: [session(legs, on: 16)],
            deloadDays: [day(20), day(21), day(22)]
        )))

        #expect(week.days.map(\.isDeload) == [false, false, false, false, true, true, true])
        #expect(week.sessionsDone == 1 && week.sessionsPlanned == 1)
    }

    @Test func todayAlreadyDoneShowsInItsDay() throws {
        let week = try #require(progress(.init(
            strength: [PlannedStrength(day: day(18), routineID: legs)], sessions: [session(legs, on: 18)]
        )))

        #expect(week.days[2].done == .strength && week.days[2].isToday)
        #expect(week.sessionsDone == week.sessionsPlanned)
    }
}
