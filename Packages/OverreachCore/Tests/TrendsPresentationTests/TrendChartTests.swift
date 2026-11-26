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
        let days = [1, 2, 5, 6, 7].map { offset in day(-offset) { $0.restingHeartRate = 52 } }
        let chart = try #require(await model(days: days).recoveryCharts.first { $0.kind == .restingHeartRate })
        #expect(chart.segments.map(\.count) == [3, 2])
        #expect(chart.values.count == 30)
        #expect(Array(chart.values.suffix(8)) == [52, 52, 52, nil, nil, 52, 52, nil])
        #expect(chart.summary.contains("5 of 30 days have a reading"))
        let today = CalendarDay(now, calendar: calendar)
        #expect(chart.dateDomain?.lowerBound == today.adding(days: -29, calendar: calendar).startDate(in: calendar))
        #expect(chart.dateDomain?.upperBound == today.startDate(in: calendar))
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

    @Test func referenceBoundsFromAnotherSourceAreNotUsed() async throws {
        let garmin = day(0) {
            $0.sources = [.garmin]
            $0.hrvRMSSDMs = 48
        }
        let apple = day(0) {
            $0.hrvSDNNMs = 52
            $0.hrvBaselineLowMs = 40
            $0.hrvBaselineHighMs = 60
        }
        let chart = try #require(await model(days: [garmin, apple]).recoveryCharts.first { $0.kind == .hrv })
        #expect(chart.segments.flatMap { $0 }.map(\.value) == [48])
        #expect(chart.band == nil)
    }

    @Test func aSourceChangeLeavesARecoveryGap() async throws {
        let days = [
            day(-2) { $0.restingHeartRate = 60 },
            day(-1) { $0.sources = [.garmin]; $0.restingHeartRate = 58 },
            day(0) { $0.restingHeartRate = 57 },
        ]
        let chart = try #require(await model(days: days).recoveryCharts.first { $0.kind == .restingHeartRate })
        #expect(chart.segments.map { $0.map(\.value) } == [[60], [57]])
    }

    @Test func daytimeHRVDoesNotFillAnOvernightGap() async throws {
        let days = (0..<30).map { offset in
            day(-offset) {
                $0.hrvSDNNMs = offset == 1 ? 95 : 48
                $0.hrvSDNNWindow = offset == 1 ? .daytime : .sleep
            }
        }
        let chart = try #require(await model(days: days).recoveryCharts.first { $0.kind == .hrv })
        #expect(chart.segments.map(\.count) == [28, 1])
        #expect(chart.segments.flatMap { $0 }.allSatisfy { $0.value == 48 })
    }

    @Test func olderReadingsKeepTheIntervalPickerAvailable() async throws {
        let model = await model(days: [day(-65) { $0.hrvSDNNMs = 48 }])
        #expect(model.showsRecoveryTrends)
        #expect(model.showsRecovery)
        #expect(!model.recoveryCharts.contains { $0.hasData })
        model.selectTrendRange(.days90)
        let chart = try #require(model.recoveryCharts.first { $0.kind == .hrv })
        #expect(chart.segments.flatMap { $0 }.map(\.value) == [48])
    }

    @Test func weeklyRunningDistanceAgreesWithRecentLoad() async throws {
        let run = { (offset: Int, id: String, source: DataSourceKind) in
            RunActivity(
                id: id, source: source,
                startedAt: now.addingTimeInterval(Double(offset) * 86_400 - 3_600), durationSeconds: 1_800,
                distanceMeters: 5_000
            )
        }
        let model = await model(runs: [
            run(-1, "a", .appleHealth), run(-1, "mirror", .garmin), run(-3, "b", .appleHealth),
            run(-10, "c", .appleHealth), run(-24, "d", .appleHealth), run(-29, "e", .appleHealth),
            run(-89, "f", .appleHealth),
        ])

        #expect(model.loadRows.first { $0.kind == .running }?.value == "2 runs · 10 km")
        let chart = try #require(model.weeklyCharts.first { $0.kind == .runningDistance })
        #expect(chart.unit == "km" && chart.interval == "Last 30 days")
        #expect(chart.segments.first?.map(\.value) == [5, 5, 0, 5, 10])
        #expect(chart.partialWeekLabel == "First bar covers 2 days: 5 km.")
        model.selectTrendRange(.days90)
        let longer = try #require(model.weeklyCharts.first { $0.kind == .runningDistance })
        #expect(longer.segments.first?.count == 13 && longer.segments.first?.last?.value == 10)
        #expect(longer.partialWeekLabel == "First bar covers 6 days: 5 km.")
    }

    @Test func aSparseHistoryHasNoWeeklyBarsToDraw() async throws {
        let model = await model()
        #expect(model.weeklyCharts.allSatisfy { !$0.hasData })
        #expect(model.weeklyCharts.first?.summary == "Strength sets per week: nothing recorded in the last 30 days.")
    }
}
