import Domain
import Foundation
import Testing
import TrendsPresentation

private actor Source: MetricsSource {
    nonisolated let kind: DataSourceKind = .appleHealth
    let days: [DailyMetrics]
    let runList: [RunActivity]

    init(days: [DailyMetrics] = [], runs: [RunActivity] = []) {
        self.days = days
        runList = runs
    }

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runList }
}

@MainActor
@Suite("Trend charts")
struct TrendChartTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, _ change: (inout DailyMetrics) -> Void) -> DailyMetrics {
        var metrics = DailyMetrics(
            day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar), sources: [.appleHealth]
        )
        change(&metrics)
        return metrics
    }

    private func model(days: [DailyMetrics] = [], runs: [RunActivity] = []) async -> RecoveryProgressModel {
        let model = RecoveryProgressModel(sources: [Source(days: days, runs: runs)], calendar: calendar)
        await model.load(now: now)
        return model
    }

    @Test func eachChartNamesItsMetricUnitIntervalAndKeyValues() async throws {
        let days = (0..<40).map { offset in day(-offset) { $0.restingHeartRate = 50 + Double(offset % 3) } }
        let model = await model(days: days)

        let chart = try #require(model.recoveryCharts.first { $0.kind == .restingHeartRate })
        #expect(chart.title == "Resting HR" && chart.unit == "bpm" && chart.interval == "Last 30 days")
        #expect(chart.summary.contains("average 51 bpm"))
        #expect(chart.summary.contains("from 50 bpm to 52 bpm"))
        #expect(chart.summary.contains("30 of 30 days have a reading"))
    }

    @Test func theLongerIntervalReachesBeyondTheReadinessHistory() async throws {
        let days = (0..<90).map { offset in day(-offset) { $0.sleepSeconds = 7 * 3_600 } }
        let model = await model(days: days)
        #expect(try #require(model.recoveryCharts.first { $0.kind == .sleep }).segments.flatMap { $0 }.count == 30)

        model.selectTrendRange(.days90)
        let sleep = try #require(model.recoveryCharts.first { $0.kind == .sleep })
        #expect(sleep.segments.flatMap { $0 }.count == 90)
        #expect(sleep.interval == "Last 90 days")
        #expect(sleep.summary.contains("90 of 90 days"))
    }

    @Test func aDayWithoutAReadingIsAVisibleGap() async throws {
        let days = [0, 1, 2, 5, 6].map { offset in day(-offset) { $0.restingHeartRate = 52 } }
        let chart = try #require(await model(days: days).recoveryCharts.first { $0.kind == .restingHeartRate })
        #expect(chart.segments.map(\.count) == [2, 3])
        #expect(chart.summary.contains("5 of 30 days have a reading"))
    }

    @Test func withoutReadingsTheSummarySaysSoAndThereIsNothingToPlot() async throws {
        let chart = try #require(await model().recoveryCharts.first { $0.kind == .sleep })
        #expect(!chart.hasData)
        #expect(chart.summary == "Sleep: no readings in the last 30 days.")
        #expect(!(await model().recoveryCharts.contains { $0.kind == .hrv }))
    }

    @Test func aReferenceBandAppearsOnlyWhenGarminReportsOne() async throws {
        let withBand = (0..<30).map { offset in
            day(-offset) {
                $0.sources = [.garmin]
                $0.hrvRMSSDMs = 48
                $0.hrvBaselineLowMs = 40
                $0.hrvBaselineHighMs = 55
            }
        }
        let banded = try #require(await model(days: withBand).recoveryCharts.first { $0.kind == .hrv })
        #expect(banded.band == 40...55)
        let sdnn = (0..<30).map { offset in day(-offset) { $0.hrvSDNNMs = 48 } }
        let plain = try #require(await model(days: sdnn).recoveryCharts.first { $0.kind == .hrv })
        #expect(plain.band == nil)
    }

    @Test func weeklyRunningDistanceAgreesWithRecentLoad() async throws {
        let run = { (offset: Int, id: String) in
            RunActivity(
                id: id, source: .appleHealth,
                startedAt: now.addingTimeInterval(Double(offset) * 86_400 - 3_600), durationSeconds: 1_800,
                distanceMeters: 5_000
            )
        }
        let model = await model(runs: [run(-1, "a"), run(-3, "b"), run(-10, "c"), run(-24, "d")])

        #expect(model.loadRows.first { $0.kind == .running }?.value == "2 runs · 10 km")
        let chart = try #require(model.weeklyCharts.first { $0.kind == .runningDistance })
        #expect(chart.unit == "km" && chart.interval == "Last 4 weeks")
        #expect(chart.segments.first?.map(\.value) == [5, 0, 5, 10])
        model.selectTrendRange(.days90)
        let longer = try #require(model.weeklyCharts.first { $0.kind == .runningDistance })
        #expect(longer.segments.first?.count == 12 && longer.segments.first?.last?.value == 10)
    }

    @Test func aSparseHistoryHasNoWeeklyBarsToDraw() async throws {
        let model = await model()
        #expect(model.weeklyCharts.allSatisfy { !$0.hasData })
        #expect(model.weeklyCharts.first?.summary == "Strength sets per week: nothing recorded in the last 4 weeks.")
    }
}
