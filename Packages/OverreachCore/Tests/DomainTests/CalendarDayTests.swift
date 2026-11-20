import Domain
import Foundation
import Testing

@Suite("CalendarDay")
struct CalendarDayTests {
    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    @Test func formatsAsISODate() {
        #expect(CalendarDay(year: 2026, month: 3, day: 7).description == "2026-03-07")
    }

    @Test func ordersChronologically() {
        let earlier = CalendarDay(year: 2026, month: 1, day: 31)
        let later = CalendarDay(year: 2026, month: 2, day: 1)
        #expect(earlier < later)
        #expect(!(later < earlier))
    }

    @Test func addsDaysAcrossMonthAndYearBoundaries() throws {
        let calendar = try utcCalendar()
        let newYearsEve = CalendarDay(year: 2026, month: 12, day: 31)
        #expect(newYearsEve.adding(days: 1, calendar: calendar) == CalendarDay(year: 2027, month: 1, day: 1))
        #expect(newYearsEve.adding(days: -31, calendar: calendar) == CalendarDay(year: 2026, month: 11, day: 30))
    }

    @Test func roundTripsThroughDate() throws {
        let calendar = try utcCalendar()
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        #expect(CalendarDay(day.startDate(in: calendar), calendar: calendar) == day)
    }
}

@Suite("DailyMetrics")
struct DailyMetricsTests {
    @Test func mergingKeepsExistingValuesAndFillsGaps() {
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        var garmin = DailyMetrics(day: day, sources: [.garmin])
        garmin.hrvRMSSDMs = 37
        garmin.restingHeartRate = 52

        var health = DailyMetrics(day: day, sources: [.appleHealth])
        health.restingHeartRate = 54
        health.sleepSeconds = 6.5 * 3600

        let merged = garmin.merging(health)

        #expect(merged.hrvNightlyAverageMs == 37)
        #expect(merged.restingHeartRate == 52)
        #expect(merged.sleepSeconds == 6.5 * 3600)
        #expect(merged.sources == [.garmin, .appleHealth])
    }
}
