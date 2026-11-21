import Domain
import Foundation
import Testing
import TrendsPresentation

private actor DaysSource: MetricsSource {
    nonisolated let kind: DataSourceKind
    let days: [DailyMetrics]
    let fails: Bool
    let runList: [RunActivity]

    init(
        kind: DataSourceKind = .appleHealth, days: [DailyMetrics] = [], fails: Bool = false, runs: [RunActivity] = []
    ) {
        self.kind = kind
        self.days = days
        self.fails = fails
        runList = runs
    }

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        if fails { throw SourceError.offline }
        return days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runList }
}

private enum SourceError: Error, LocalizedError {
    case offline
    var errorDescription: String? { "Offline" }
}

@MainActor
@Suite("Recovery & Progress")
struct RecoveryProgressModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, _ change: (inout DailyMetrics) -> Void) -> DailyMetrics {
        var metrics = DailyMetrics(
            day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar), sources: [.appleHealth]
        )
        change(&metrics)
        return metrics
    }

    @Test func beforeLoadingItHasNothingToShow() {
        let model = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        #expect(!model.hasLoaded && model.readings.isEmpty)
        #expect(model.recoverySummary == "Loading…")
    }

    @Test func withoutAnySourceDataEveryReadingSaysItIsMissing() async {
        let model = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        await model.load(now: now)
        #expect(model.hasNoReadings)
        #expect(model.readings.map(\.kind) == [.hrv, .restingHeartRate, .sleep])
        #expect(model.readings.allSatisfy { !$0.isAvailable && $0.value == "No reading" })
        #expect(model.recoverySummary == "No readings yet")
    }

    @Test func aReadingShowsItsSourceLastUpdateAndCoverage() async {
        let days = (0..<30).map { offset in
            day(-offset) {
                $0.restingHeartRate = 52
                $0.sleepSeconds = 7.5 * 3_600
                $0.hrvSDNNMs = 50
            }
        }
        let model = RecoveryProgressModel(sources: [DaysSource(days: days)], calendar: calendar)
        await model.load(now: now)

        let resting = model.readings.first { $0.kind == .restingHeartRate }
        #expect(resting?.isAvailable == true)
        #expect(resting?.value == "52 bpm")
        #expect(resting?.summary == "Within your usual range")
        #expect(resting?.details.contains { $0.hasPrefix("From Apple Health") } == true)
        #expect(resting?.details.contains { $0.hasPrefix("Latest reading:") } == true)
        #expect(resting?.details.contains { $0.hasPrefix("Usual:") } == true)
        #expect(model.readings.first { $0.kind == .sleep }?.value == "7.5 h")
    }

    @Test func aBaselineStillBeingBuiltIsExplainedNotJudged() async {
        let model = RecoveryProgressModel(
            sources: [DaysSource(days: [day(0) { $0.restingHeartRate = 55 }])], calendar: calendar
        )
        await model.load(now: now)
        let resting = model.readings.first { $0.kind == .restingHeartRate }
        #expect(resting?.summary.hasPrefix("Still building your usual range") == true)
    }

    @Test func aStaleReadingNamesItsLatestDay() async {
        let model = RecoveryProgressModel(
            sources: [DaysSource(days: [day(-5) { $0.restingHeartRate = 55 }])], calendar: calendar
        )
        await model.load(now: now)
        let resting = model.readings.first { $0.kind == .restingHeartRate }
        #expect(resting?.summary == "No recent reading")
        #expect(resting?.details.contains { $0.hasPrefix("Latest reading:") } == true)
    }

    @Test func aFailingSourceKeepsTheOthersVisibleAndIsReported() async {
        let health = DaysSource(days: [day(0) { $0.sleepSeconds = 8 * 3_600 }])
        let garmin = DaysSource(kind: .garmin, fails: true)
        let model = RecoveryProgressModel(sources: [garmin, health], calendar: calendar)
        await model.load(now: now)

        #expect(model.showsFailure)
        #expect(model.failureLines == ["Garmin: Offline"])
        #expect(model.readings.first { $0.kind == .sleep }?.value == "8 h")
    }

    @Test func garminEstimatesAreLabelledAsEstimates() async {
        let model = RecoveryProgressModel(
            sources: [DaysSource(kind: .garmin, days: [day(0) {
                $0.bodyBatteryHigh = 80
                $0.vo2Max = 52.4
                $0.sources = [.garmin]
            }])],
            calendar: calendar
        )
        await model.load(now: now)
        let battery = model.readings.first { $0.kind == .bodyBattery }
        #expect(battery?.summary == "Garmin's estimate")
        #expect(battery?.details.first == "From Garmin")
        #expect(model.readings.first { $0.kind == .vo2Max }?.value == "52.4")
    }

    @Test func recentLoadCountsEachRunOnceAgainstTheUsualWeek() async {
        let run = { (offset: Int, id: String) in
            RunActivity(
                id: id, source: .appleHealth,
                startedAt: now.addingTimeInterval(Double(offset) * 86_400 - 3_600), durationSeconds: 1_800,
                distanceMeters: 5_000
            )
        }
        let runs = [run(-1, "a"), run(-3, "b"), run(-10, "c"), run(-17, "d"), run(-24, "e")]
        let model = RecoveryProgressModel(sources: [DaysSource(runs: runs)], calendar: calendar)
        await model.load(now: now)

        let running = model.loadRows.first { $0.kind == .running }
        #expect(running?.value == "2 runs · 10 km")
        #expect(running?.comparison?.hasPrefix("Usual week: 1 runs") == true)
        #expect(model.recentLoadSummary == "Running: 2 runs · 10 km")
    }

    @Test func withoutTrainingTheLoadSectionIsEmpty() async {
        let model = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        await model.load(now: now)
        #expect(!model.showsRecentLoad)
        #expect(model.recentLoadSummary == "No training in the last weeks")
    }
}
