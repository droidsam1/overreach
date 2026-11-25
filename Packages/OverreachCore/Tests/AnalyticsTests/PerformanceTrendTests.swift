import Analytics
import Domain
import Foundation
import Testing

struct PerformanceTrendTests {
    private typealias Point = PerformanceTrend.Observation
    private typealias Label = PerformanceTrend.Label
    private let calendar = Calendar(identifier: .iso8601)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(daysAgo: Int) -> Date {
        CalendarDay(now, calendar: calendar).adding(days: -daysAgo, calendar: calendar).startDate(in: calendar)
    }

    private func observations(
        _ values: [Double], changedKey: String? = nil, daysAgo: [Int] = [49, 42, 35, 21, 14, 7]
    ) -> [Point] {
        zip(daysAgo, values).enumerated().map { index, sample in
            Point(sessionID: String(index), date: date(daysAgo: sample.0), value: sample.1,
                  comparisonKey: index >= 3 ? changedKey ?? "same" : "same")
        }
    }

    @Test(arguments: [
        ([99.0, 100, 101, 105, 106, 107], Label.improving),
        ([99.0, 100, 101, 93, 94, 95], Label.declining),
        ([92.0, 100, 107, 95, 102, 105], Label.withinVariability),
        ([99.0, 100, 101, 99.5, 100, 102], Label.possiblePlateau),
        ([100.0, 100, 100, 100, 100, 100], Label.insufficientEvidence),
        ([99.0, 100, 101, 99.5, 100], Label.insufficientEvidence)
    ]) func replaysStrengthChanges(values: [Double], expected: PerformanceTrend.Label) {
        let context = PerformanceTrend.StrengthContext(through: now, calendar: calendar)
        #expect(PerformanceTrend.strength(observations(values), context: context) == expected)
    }

    @Test func changedVariantOrEquationSuppressesTrend() {
        let context = PerformanceTrend.StrengthContext(through: now, calendar: calendar)
        let values = [99.0, 100, 101, 99.5, 100, 102]
        for key in ["bench paused", "bench v2", "bench per side"] {
            #expect(PerformanceTrend.strength(observations(values, changedKey: key), context: context)
                == .insufficientEvidence)
        }
    }

    @Test func clusteredSessionsCannotStandForSixWeeks() {
        let context = PerformanceTrend.StrengthContext(through: now, calendar: calendar)
        let values = [99.0, 100, 101, 99.5, 100, 102]
        let points = observations(values, daysAgo: [30, 29, 28, 27, 26, 25])
        #expect(PerformanceTrend.strength(points, context: context) == .insufficientEvidence)
    }

    @Test func activeDeloadsAndBlockChangesSuppressPlateau() {
        let points = observations([99, 100, 101, 99.5, 100, 102])
        let day = CalendarDay(date(daysAgo: 24), calendar: calendar)
        let deload = AthleteProfile(deloads: [DeloadRecord(start: day, days: 7)])
        let accepted = DeloadDecision(
            start: day, end: day, reason: .reducedStrength, accepted: true, discipline: .strength
        )
        let inferred = AthleteProfile(deloadDecisions: [accepted])
        let block = AthleteProfile(declaredBlocks: [TrainingBlock(focus: .strength, start: day, isDeclared: true)])
        for profile in [deload, inferred, block] {
            let context = PerformanceTrend.StrengthContext(through: now, profile: profile, calendar: calendar)
            #expect(PerformanceTrend.strength(points, context: context) == .insufficientEvidence)
        }
        let runOnly = DeloadDecision(start: day, end: day, reason: .easyRuns, accepted: true, discipline: .running)
        let profile = AthleteProfile(deloadDecisions: [runOnly], restDays: [day])
        let context = PerformanceTrend.StrengthContext(through: now, profile: profile, calendar: calendar)
        #expect(PerformanceTrend.strength(points, context: context) == .possiblePlateau)
    }

    @Test func heartRateReplaysRejectSensorSwitchAndTrackMeaningfulChange() {
        let better = observations([151, 150, 149, 144, 145, 146])
        let noisy = observations([148, 151, 154, 145, 149, 153])
        let sensorSwitch = observations([151, 150, 149, 144, 145, 146], changedKey: "chest strap")
        for (points, expected) in [(better, Label.improving), (noisy, .withinVariability),
                                   (sensorSwitch, .insufficientEvidence)] {
            #expect(PerformanceTrend.runningHeartRate(points, through: now, windowDays: 28, calendar: calendar)
                == expected)
        }
    }

    @Test func repeatedImportsDoNotInflateCoverage() {
        let points = observations([151, 150, 149, 144, 145])
        let duplicates = points + Array(points.suffix(2))
        #expect(PerformanceTrend.runningHeartRate(duplicates, through: now, windowDays: 28, calendar: calendar)
            == .insufficientEvidence)
    }
}
