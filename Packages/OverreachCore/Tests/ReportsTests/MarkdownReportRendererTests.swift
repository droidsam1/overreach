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

    @Test func strengthSessionExplainsTheRotationAdjustment() {
        let report = TrainingReport(
            generatedAt: .now,
            recentSessions: [
                SessionSummary(
                    day: CalendarDay(year: 2026, month: 11, day: 17), name: "Deadlift", tonnageKg: 2_000,
                    effectiveSets: [.hamstrings: 3], rotationAdjustments: [
                        .init(action: .postponed, carryover: .notable, reason: .runCarryover),
                        .init(action: .capped, carryover: .light, reason: .readiness, maximumRPE: 8),
                    ]
                ),
            ]
        )
        let markdown = MarkdownReportRenderer.render(report)
        let postponement = "Rotation postponed · run carry-over notable · residual fatigue from the recorded run"
        #expect(markdown.contains(postponement))
        #expect(markdown.contains("Rotation capped · run carry-over light · reduced readiness · maximum RPE 8.0"))
    }

    @Test func runsListTheWatchSplitOnlyWhenPresent() throws {
        let calendar = try utcCalendar()
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        let start = day.startDate(in: calendar).addingTimeInterval(3_600)
        let split = RunActivity(
            id: "g", source: .garmin, startedAt: start, durationSeconds: 2_400, distanceMeters: 4_800, lapCount: 5,
            movingDurationSeconds: 2_330,
            runWalk: RunWalkSplits(
                running: .init(distanceMeters: 3_600, durationSeconds: 1_440, segments: 4, longestSegmentMeters: 1_250),
                walking: .init(distanceMeters: 1_200, durationSeconds: 900, segments: 3)
            )
        )
        let plain = RunActivity(
            id: "h", source: .appleHealth, startedAt: start.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let report = TrainingReport(generatedAt: start, recentRuns: [split, plain])

        let lines = MarkdownReportRenderer.render(report, calendar: calendar).split(separator: "\n")

        let withSplit = try #require(lines.first { $0.hasPrefix("- 2026-11-16") })
        #expect(withSplit.hasSuffix("; running 3.60 km in 24 min, walking 1.20 km in 15 min, "
            + "longest continuous run 1.25 km, running pace 6:40 /km, moving 39 min, 5 laps"))
        let withoutSplit = try #require(lines.first { $0.hasPrefix("- 2026-11-15") })
        #expect(withoutSplit.hasSuffix("load –"))
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

    @Test func reportsOmitPrivateCheckInReasonsAndTheDecisionsTheyOverride() {
        let readiness = Readiness(level: .red, reasons: [.exerciseWarningSigns])
        let markdown = MarkdownReportRenderer.render(TrainingReport(generatedAt: .now, readiness: readiness))

        #expect(!markdown.contains("Readiness: **red**"))
        #expect(!markdown.contains("10.1136/bjsports-2022-105759"))
    }

    @Test func readinessReportListsEachInputWithItsProvenance() {
        let day = CalendarDay(year: 2026, month: 11, day: 16)
        let readiness = Readiness(level: .amber, reasons: [.hrvBelowBaseline(nights: 4)], inputs: [
            ReadinessInputAudit(
                input: .hrv(HRVSeriesID(.rmssd, .sleep)), status: .compared, source: .garmin, latestDay: day,
                value: 34.6, recentDays: 7, recentReadings: 5, rejectedReadings: 1,
                reference: ReadinessReference(
                    kind: .personalBaseline, days: 60, readings: 24, minimumReadings: 14, overlappingReadings: 4,
                    value: 43.2
                ),
                outcome: .below
            ),
            ReadinessInputAudit(
                input: .hrv(HRVSeriesID(.sdnn, .sleep)), status: .stale, source: .appleHealth,
                latestDay: CalendarDay(year: 2026, month: 11, day: 2), recentDays: 7
            ),
            ReadinessInputAudit(input: .sleep, status: .missing),
        ])
        let markdown = MarkdownReportRenderer.render(TrainingReport(generatedAt: .now, readiness: readiness))

        #expect(markdown.contains(
            "    - HRV (RMSSD, sleep) from Garmin: compared; latest 2026-11-16; recent mean 35 ms; "
                + "5 usable readings in the last 7 days; baseline 43 ms from 24 readings over 60 days (minimum 14), "
                + "4 of them inside the recent window; 1 implausible readings ignored; below the reference"
        ))
        let stale = "    - HRV (SDNN, sleep) from Apple Health: no recent data, not used; latest 2026-11-02"
        #expect(markdown.contains(stale))
        #expect(markdown.contains("    - Sleep: no data"))
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
