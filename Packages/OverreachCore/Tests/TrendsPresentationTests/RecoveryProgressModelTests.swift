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

private struct WalksSource: ActivitySource {
    let walks: [WalkBout]

    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        [DailyActivity(day: range.upperBound, walks: walks)]
    }
}

private actor EditableRunsSource: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    private var activities: [RunActivity]

    init(_ activities: [RunActivity]) { self.activities = activities }
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { activities }
    func replace(with activities: [RunActivity]) { self.activities = activities }
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

    @Test func sleepTimingCardAppearsWithAWeekOfNights() async {
        let nights = (-9...0).map { offset in
            day(offset) { metrics in
                let wake = metrics.day.startDate(in: calendar).addingTimeInterval(7 * 3_600)
                metrics.sleepSeconds = 8 * 3_600
                metrics.sleepStart = wake.addingTimeInterval(-8 * 3_600)
                metrics.sleepEnd = wake
            }
        }
        let model = RecoveryProgressModel(sources: [DaysSource(days: nights)], calendar: calendar)
        let noon = CalendarDay(now, calendar: calendar).startDate(in: calendar).addingTimeInterval(12 * 3_600)
        await model.load(now: noon)
        #expect(model.sleepTiming?.rows.count == 2)
        #expect(model.sleepTiming?.summary == "Your sleep and training times look steady.")
        #expect(model.sleepTiming?.observations.isEmpty == true)

        let empty = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        await empty.load(now: now)
        #expect(empty.sleepTiming == nil)
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
        #expect(model.sectionHintCandidates == nil)

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

    @Test func recentLoadShowsWalkingEvenWithoutSteps() async {
        let lastWalk = WalkBout(
            start: CalendarDay(now, calendar: calendar).startDate(in: calendar), durationSeconds: 1_800,
            source: .garmin
        )
        let loadTime = lastWalk.end
        let model = RecoveryProgressModel(sources: [], activity: [WalksSource(walks: [lastWalk])], calendar: calendar)
        await model.load(now: loadTime)

        let movement = model.loadRows.first { $0.kind == .movement }
        #expect(model.showsRecentLoad)
        #expect(movement?.details == ["Walking today: 30 min", "From Garmin"])
    }

    @Test func recentLoadComparesWalkingWithTheUsualDay() async {
        let today = CalendarDay(now, calendar: calendar)
        let walks = (-14...0).map { offset in
            WalkBout(
                start: today.adding(days: offset, calendar: calendar).startDate(in: calendar),
                durationSeconds: offset == 0 ? 3_600 : 1_800, source: .appleHealth
            )
        }
        let model = RecoveryProgressModel(
            sources: [], activity: [WalksSource(walks: walks)], calendar: calendar
        )
        await model.load(now: today.startDate(in: calendar).addingTimeInterval(3_600))

        let movement = model.loadRows.first { $0.kind == .movement }
        #expect(movement?.details.contains("Walking today: 60 min. Usually 30 min a day.") == true)
    }

    @Test func runningProgressRefreshesAndRetainsTheSourceSession() async {
        let recent = RunActivity(
            id: "recent", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400),
            durationSeconds: 1_400, distanceMeters: 5_000, elapsedSeconds: 1_500, kind: .training
        )
        let previous = RunActivity(
            id: "previous", source: .appleHealth, startedAt: now.addingTimeInterval(-35 * 86_400),
            durationSeconds: 1_600, distanceMeters: 5_000, elapsedSeconds: 1_600, kind: .training
        )
        let source = EditableRunsSource([recent, previous, recent])
        let model = RecoveryProgressModel(sources: [source], calendar: calendar)
        model.performanceRange = .days30
        await model.load(now: now)
        let initial = model.runningPerformance.first { $0.id == "training" }
        #expect(model.showsProgress)
        #expect(initial?.best?.id == .run(recent))
        #expect(initial?.best?.valueText == "25:00")
        #expect(initial?.comparison == "Median change −1:40 · Sessions this period 1 · Previous period 1")
        #expect(model.comparableHeartRate == nil)

        await source.replace(with: [previous])
        await model.load(now: now)
        #expect(model.runningPerformance.first { $0.id == "training" }?.best == nil)
        model.performanceRange = .days90
        #expect(model.runningPerformance.first { $0.id == "training" }?.best?.id == .run(previous))
    }

    @Test func garminSensorConfirmationEnablesApproximateComparisonAndSessionLinks() async {
        let runs = [-2, -35].map { offset in
            RunActivity(
                id: String(offset), source: .garmin, startedAt: now.addingTimeInterval(Double(offset) * 86_400),
                durationSeconds: 240, distanceMeters: 800, kind: .training
            )
        }
        var saved: [String: String] = [:]
        let model = RecoveryProgressModel(
            sources: [DaysSource(kind: .garmin, runs: runs)], calendar: calendar,
            runningTrack: { run in
                let heartRate: Double = run.id == "-2" ? 142 : 150
                let samples = (0...240).map { second in
                    RunningTrack.Sample(
                        date: run.startedAt.addingTimeInterval(Double(second)),
                        distanceMeters: Double(second) * 10 / 3, speedMetersPerSecond: 10 / 3,
                        altitudeMeters: 20, heartRateBPM: heartRate, cadenceStepsPerMinute: 170
                    )
                }
                return RunningTrack(samples: samples)
            },
            savePulseSensors: { saved = $0 }
        )
        model.performanceRange = .days30
        await model.load(now: now)
        #expect(model.comparableHeartRate == nil)
        #expect(model.runningPulseSensorRows.count == 2)
        for run in runs { model.choosePulseSensor(.watch, for: run.id) }
        #expect(saved == ["-2": "watch", "-35": "watch"])
        let series = model.comparableHeartRate
        #expect(series?.comparison.hasPrefix("Approximate comparison · Median change −8 bpm") == true)
        #expect(series?.points.map(\.id) == [.run(runs[1]), .run(runs[0])])
        #expect(series?.trend == "Insufficient evidence for a trend")
        model.choosePulseSensor(.strap, for: runs[0].id)
        #expect(model.comparableHeartRate == nil)
    }

    @Test func withoutTrainingTheLoadSectionIsEmpty() async {
        let model = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        await model.load(now: now)
        #expect(!model.showsRecentLoad)
        #expect(model.recentLoadSummary == "No training in the last weeks")
    }
}

@MainActor
@Suite("Recovery & Progress: sections by data")
struct RecoveryProgressSectionsTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    @Test func withNoDataNoSectionShowsAndOneLineSaysWhatUnlocksThem() async {
        let model = RecoveryProgressModel(sources: [DaysSource()], calendar: calendar)
        #expect(model.unlockHint == nil)
        await model.load(now: now)
        #expect(!model.showsRecovery && !model.showsRecentLoad && !model.showsProgress)
        #expect(!model.showsRecoveryTrends && !model.showsLoadTrends)
        #expect(model.unlockHint != nil)
    }

    @Test func readingsUnlockRecoveryAndItsCharts() async {
        var metrics = DailyMetrics(day: CalendarDay(now, calendar: calendar), sources: [.appleHealth])
        metrics.sleepSeconds = 7 * 3_600
        let model = RecoveryProgressModel(sources: [DaysSource(days: [metrics])], calendar: calendar)
        await model.load(now: now)
        #expect(model.showsRecovery && model.showsRecoveryTrends)
        #expect(!model.showsRecentLoad && !model.showsLoadTrends)
        #expect(model.unlockHint == nil)
    }

    @Test func aRunUnlocksRecentLoad() async {
        let run = RunActivity(
            id: "r", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let model = RecoveryProgressModel(sources: [DaysSource(runs: [run])], calendar: calendar)
        await model.load(now: now)
        #expect(model.showsRecentLoad && model.showsLoadTrends)
        #expect(!model.showsRecovery)
    }
}
