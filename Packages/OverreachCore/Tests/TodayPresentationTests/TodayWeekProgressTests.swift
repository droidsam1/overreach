import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

private struct QuietSource: MetricsSource {
    let kind = DataSourceKind.appleHealth
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

/// The "Your week" card of Today (ADR-0042).
@MainActor
@Suite("Today: your week")
struct TodayWeekProgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()
    private let format = Format(locale: Locale(identifier: "en_US"))

    /// Wednesday 18 November 2026 at noon: the week runs from Monday 16 to Sunday 22.
    private var now: Date { day(18).startDate(in: calendar).addingTimeInterval(12 * 3_600) }

    private func day(_ number: Int) -> CalendarDay {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: number)) ?? .distantPast
        return CalendarDay(date, calendar: calendar)
    }

    private func finished(_ routine: Routine, on number: Int) -> StrengthSession {
        let start = day(number).startDate(in: calendar).addingTimeInterval(8 * 3_600)
        return StrengthSession(
            name: routine.name, startedAt: start, endedAt: start.addingTimeInterval(3_600), routineID: routine.id
        )
    }

    private func model(
        strength: [PlannedStrength] = [], runs: [PlannedRun] = [], routines: [Routine] = [],
        sessions: [StrengthSession] = [], restDays: [CalendarDay] = [], block: TrainingBlock? = nil
    ) async throws -> TodayModel {
        var goal = TrainingGoal(kind: .hybrid)
        goal.setStrengthSchedule(strength)
        goal.setRunningSchedule(runs)
        let store = TestStore(sessions: sessions, routines: routines)
        try await store.save(AthleteProfile(goal: goal, declaredBlocks: block.map { [$0] } ?? [], restDays: restDays))
        let model = TodayModel(
            sources: [QuietSource()], profiles: store, workouts: store, routines: store, calendar: calendar,
            format: format
        )
        await model.load(now: now)
        return model
    }

    @Test func withoutAPlanOrTrainingThereIsNoCard() async throws {
        #expect(try await model().yourWeek == nil)
    }

    @Test func aPlannedWeekShowsDaysProgressAndTodaysSession() async throws {
        let upper = Routine(name: "Upper")
        let lower = Routine(name: "Lower")
        let loaded = try await model(
            strength: [
                PlannedStrength(day: day(16), routineID: lower.id), PlannedStrength(day: day(18), routineID: upper.id),
            ],
            routines: [upper, lower], sessions: [finished(lower, on: 16)],
            block: TrainingBlock(focus: .strength, start: day(9), plannedWeeks: 4, isDeclared: true)
        )
        let week = try #require(loaded.yourWeek)

        #expect(week.days.count == 7)
        #expect(week.days.map(\.label) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(week.days[0].kind == .strength)
        #expect(week.days[2].kind == .planned && week.days[2].isToday)
        #expect(week.blockTitle == "Strength block · week 2 of 4")
        #expect(week.fraction == 0.5)
        #expect(week.strengthSegment == 0.5 && week.runSegment == 0)
        #expect(week.summary == "1 of 2 sessions · today completes this week's strength")
        #expect(week.session?.title == "Strength · Upper")
        #expect(week.session?.tag == .today)
    }

    @Test func restLoggedCountsAsACompletedDayWithoutAStreak() async throws {
        let upper = Routine(name: "Upper")
        let loaded = try await model(
            strength: [PlannedStrength(day: day(20), routineID: upper.id)], routines: [upper], restDays: [day(17)]
        )
        let week = try #require(loaded.yourWeek)

        #expect(week.days[1].kind == .restLogged)
        #expect(week.summary == "0 of 1 sessions")
    }

    @Test func todayAlreadyDoneHasNoSessionRow() async throws {
        let upper = Routine(name: "Upper")
        let loaded = try await model(
            strength: [PlannedStrength(day: day(18), routineID: upper.id)], routines: [upper],
            sessions: [finished(upper, on: 18)]
        )
        let week = try #require(loaded.yourWeek)

        #expect(week.days[2].kind == .strength)
        #expect(week.session == nil)
        #expect(week.fraction == 1)
    }

    @Test func aWeekWithOnlyUnplannedTrainingStillShowsTheStrip() async throws {
        let upper = Routine(name: "Upper")
        let loaded = try await model(sessions: [finished(upper, on: 17)])
        let week = try #require(loaded.yourWeek)

        #expect(week.days[1].kind == .strength)
        #expect(week.summary == "Days trained this week: 1")
        #expect(week.session == nil)
    }
}
