@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Workload")
struct WorkloadTests {
    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    private func constantLoads(days: Int, load: Double, endingOn end: CalendarDay, calendar: Calendar) -> [DailyLoad] {
        (0..<days).map { DailyLoad(day: end.adding(days: -$0, calendar: calendar), load: load) }
    }

    @Test func sessionRPELoadMultipliesRPEByMinutes() {
        #expect(Workload.sessionRPELoad(rpe: 7, durationMinutes: 60) == 420)
        #expect(Workload.sessionRPELoad(rpe: -1, durationMinutes: 60) == 0)
    }

    @Test func steadyLoadGivesRatioOfOne() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        let loads = constantLoads(days: 28, load: 100, endingOn: today, calendar: calendar)

        let change = try #require(Workload.weeklyLoadChange(loads: loads, on: today, calendar: calendar))
        #expect(abs(change.ratio - 1) < 0.0001)
        #expect(abs(change.lastWeek - 700) < 0.0001)
        #expect(abs(change.usualWeek - 700) < 0.0001)
    }

    @Test func lastWeekIsNotPartOfTheUsualWeek() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        var loads = constantLoads(days: 28, load: 100, endingOn: today, calendar: calendar)
        loads += constantLoads(days: 7, load: 100, endingOn: today, calendar: calendar)  // last week doubled

        let change = try #require(Workload.weeklyLoadChange(loads: loads, on: today, calendar: calendar))
        // Uncoupled: exactly 2×. The coupled ratio would give 1400 / 875 = 1.6.
        #expect(abs(change.ratio - 2) < 0.0001)
    }

    @Test func ignoresLoadsAfterTheDayAndBeforeTheWindow() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        var loads = constantLoads(days: 28, load: 100, endingOn: today, calendar: calendar)
        loads.append(DailyLoad(day: today.adding(days: 1, calendar: calendar), load: 10_000))
        loads.append(DailyLoad(day: today.adding(days: -28, calendar: calendar), load: 10_000))

        let change = try #require(Workload.weeklyLoadChange(loads: loads, on: today, calendar: calendar))
        #expect(abs(change.ratio - 1) < 0.0001)
    }

    @Test func noUsualLoadReturnsNil() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        #expect(Workload.weeklyLoadChange(loads: [], on: today, calendar: calendar) == nil)
        // Only this week's load: nothing to compare with.
        let thisWeek = constantLoads(days: 7, load: 100, endingOn: today, calendar: calendar)
        #expect(Workload.weeklyLoadChange(loads: thisWeek, on: today, calendar: calendar) == nil)
    }
}
