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

        let ratio = try #require(Workload.acuteChronicRatio(loads: loads, on: today, calendar: calendar))
        #expect(abs(ratio - 1) < 0.0001)
    }

    @Test func loadSpikeRaisesTheRatio() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        var loads = constantLoads(days: 28, load: 100, endingOn: today, calendar: calendar)
        loads += constantLoads(days: 7, load: 100, endingOn: today, calendar: calendar)  // last week doubled

        let ratio = try #require(Workload.acuteChronicRatio(loads: loads, on: today, calendar: calendar))
        #expect(ratio > 1.5)
    }

    @Test func ignoresLoadsAfterTheDay() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        var loads = constantLoads(days: 28, load: 100, endingOn: today, calendar: calendar)
        loads.append(DailyLoad(day: today.adding(days: 1, calendar: calendar), load: 10_000))

        let ratio = try #require(Workload.acuteChronicRatio(loads: loads, on: today, calendar: calendar))
        #expect(abs(ratio - 1) < 0.0001)
    }

    @Test func noChronicLoadReturnsNil() throws {
        let calendar = try utcCalendar()
        let today = CalendarDay(year: 2026, month: 11, day: 16)
        #expect(Workload.acuteChronicRatio(loads: [], on: today, calendar: calendar) == nil)
    }
}
