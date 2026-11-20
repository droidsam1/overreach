import Domain
import Foundation
@testable import Reports
import Testing

@Suite("Markdown report")
struct MarkdownReportRendererTests {
    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        return calendar
    }

    @Test func rendersSectionsAndQuestion() throws {
        let calendar = try utcCalendar()
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        var today = DailyMetrics(day: day, sources: [.garmin])
        today.hrvRMSSDMs = 37
        today.hrvBaselineLowMs = 40
        today.hrvBaselineHighMs = 48

        let report = TrainingReport(
            generatedAt: day.startDate(in: calendar),
            athleteContext: "Hybrid athlete, 4 runs + 3 gym sessions per week.",
            today: today,
            readiness: Readiness(level: .amber, reasons: [.hrvBelowBaseline(nights: 4)]),
            recentDays: [today],
            checkIns: [CheckIn(day: day, isSick: true, energy: 2)],
            question: "Should I run today?"
        )

        let markdown = MarkdownReportRenderer.render(report, calendar: calendar)

        #expect(markdown.contains("# Overreach training report"))
        #expect(markdown.contains("Generated: 2026-11-16"))
        #expect(markdown.contains("## Athlete context"))
        #expect(markdown.contains("Readiness: **amber**"))
        #expect(markdown.contains("HRV below its normal range for 4 nights"))
        #expect(markdown.contains("HRV last night: 37 ms RMSSD (watch-reported range 40–48 ms)"))
        #expect(markdown.contains("| 2026-11-16 | 37 RMSSD | – |"))
        #expect(markdown.contains("2026-11-16: sick; energy 2/5"))
        #expect(markdown.hasSuffix("## Question\n\nShould I run today?\n"))
    }

    @Test func missingValuesRenderAsDash() {
        #expect(MarkdownReportRenderer.format(nil, decimals: 0) == "–")
        #expect(MarkdownReportRenderer.format(.nan, decimals: 0) == "–")
        #expect(MarkdownReportRenderer.format(6.4, decimals: 1) == "6.4")
        #expect(MarkdownReportRenderer.format(37.4, decimals: 0) == "37")
    }

    @Test func readinessReportUsesComparableHRVReadings() {
        let coverage = HRVCoverage(
            metric: .rmssd, latestDay: CalendarDay(year: 2026, month: 11, day: 16),
            recentDays: 7, recentReadings: 5, minimumRecentReadings: 3,
            baselineDays: 60, baselineReadings: 24, minimumBaselineReadings: 14
        )
        let readiness = Readiness(level: .amber, reasons: [.hrvBelowBaseline(nights: 4)], hrvCoverage: coverage)
        let markdown = MarkdownReportRenderer.render(TrainingReport(generatedAt: .now, readiness: readiness))

        #expect(markdown.contains("HRV (RMSSD, Garmin) below its normal range (4 of 5 comparable readings low in the last 7 days)"))
        #expect(markdown.contains("[research source](https://doi.org/10.3390/ijerph181910299)"))
    }

    @Test func formatsPaceAsMinutesAndSeconds() {
        #expect(MarkdownReportRenderer.formatPace(305) == "5:05 /km")
        #expect(MarkdownReportRenderer.formatPace(nil) == "–")
    }

    @Test func emptyReportStillRenders() {
        let markdown = MarkdownReportRenderer.render(TrainingReport(generatedAt: Date(timeIntervalSince1970: 0)))
        #expect(markdown.contains("No data for today."))
    }
}
