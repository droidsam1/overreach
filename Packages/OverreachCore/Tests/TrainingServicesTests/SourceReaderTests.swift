import Domain
import Foundation
import Testing
import TrainingServices

struct ReadFailed: LocalizedError {
    var errorDescription: String? { "offline" }
}

struct FakeSource: MetricsSource {
    let kind: DataSourceKind
    var available = true
    var fails = false
    var metrics: [DailyMetrics] = []
    var activities: [RunActivity] = []

    func isAvailable() async -> Bool { available }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        if fails { throw ReadFailed() }
        return metrics
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        if fails { throw ReadFailed() }
        return activities
    }
}

@Suite("Reading the sources")
struct SourceReaderTests {
    private let day = CalendarDay(year: 2026, month: 11, day: 20)
    private let start = Date(timeIntervalSince1970: 1_795_600_000)

    private func metrics(restingHeartRate: Double?, steps: Int?, source: DataSourceKind) -> DailyMetrics {
        var metrics = DailyMetrics(day: day)
        metrics.restingHeartRate = restingHeartRate
        metrics.steps = steps
        metrics.sources = [source]
        return metrics
    }

    private func run(_ id: String, source: DataSourceKind, heartRate: Double? = nil) -> RunActivity {
        RunActivity(
            id: id, source: source, startedAt: start, durationSeconds: 1_800, distanceMeters: 5_000,
            averageHeartRate: heartRate
        )
    }

    @Test func twoSourcesForOneDayGiveOneRecordWithTheFirstSourceWinning() async {
        let reader = SourceReader(sources: [
            FakeSource(kind: .garmin, metrics: [metrics(restingHeartRate: 48, steps: nil, source: .garmin)]),
            FakeSource(kind: .appleHealth, metrics: [metrics(restingHeartRate: 52, steps: 9_000, source: .appleHealth)])
        ])

        let reading = await reader.dailyMetrics(in: day...day)

        #expect(reading.value.count == 1)
        #expect(reading.value.first?.restingHeartRate == 48)
        #expect(reading.value.first?.steps == 9_000)
        #expect(reading.readSources == [.garmin, .appleHealth])
        #expect(!reading.failed)
    }

    @Test func daysOutsideTheRangeAreLeftOut() async {
        var outside = metrics(restingHeartRate: 50, steps: nil, source: .garmin)
        outside.day = CalendarDay(year: 2026, month: 11, day: 1)
        let reader = SourceReader(sources: [FakeSource(kind: .garmin, metrics: [outside])])

        #expect(await reader.dailyMetrics(in: day...day).value.isEmpty)
    }

    @Test func unavailableSourcesAreSkippedAndFailuresKeepTheOtherSources() async {
        let reader = SourceReader(sources: [
            FakeSource(kind: .garmin, fails: true),
            FakeSource(kind: .appleHealth, activities: [run("h1", source: .appleHealth)]),
            FakeSource(kind: .manual, available: false, fails: true)
        ])

        let reading = await reader.runs(from: .distantPast, to: .distantFuture)

        #expect(reading.activities.map(\.id) == ["h1"])
        #expect(reading.readSources == [.appleHealth])
        #expect(reading.failures == [SourceFailure(source: .garmin, reason: "offline")])
        #expect(reading.didRead)
    }

    @Test func theSameRunFromTwoSourcesAppearsOnceWithBothSources() async {
        let reader = SourceReader(sources: [
            FakeSource(kind: .appleHealth, activities: [run("h1", source: .appleHealth, heartRate: 150)]),
            FakeSource(kind: .garmin, activities: [run("g1", source: .garmin)])
        ])

        let reading = await reader.runs(from: .distantPast, to: .distantFuture)

        #expect(reading.value.count == 1)
        #expect(reading.activities.first?.source == .garmin)
        #expect(reading.activities.first?.averageHeartRate == 150)
        #expect(Set(reading.value.first?.sources ?? []) == [.garmin, .appleHealth])
    }

    @Test func noAvailableSourceMeansNothingWasRead() async {
        let reader = SourceReader(sources: [FakeSource(kind: .garmin, available: false)])
        let reading = await reader.runs(from: .distantPast, to: .distantFuture)
        #expect(!reading.didRead)
        #expect(!reading.failed)
    }
}

@Suite("Reading each source's metrics")
struct SourceReaderBySourceTests {
    private let day = CalendarDay(year: 2026, month: 11, day: 20)

    @Test func eachSourceKeepsItsOwnRowInSourceOrder() async {
        var garmin = DailyMetrics(day: day)
        garmin.setHRV(42, .rmssd)
        garmin.sources = [.garmin]
        var health = DailyMetrics(day: day)
        health.setHRV(61, .sdnn)
        health.sources = [.appleHealth]
        let reader = SourceReader(sources: [
            FakeSource(kind: .garmin, metrics: [garmin]), FakeSource(kind: .appleHealth, metrics: [health])
        ])

        let rows = await reader.dailyMetricsBySource(in: day...day).value

        #expect(rows.map(\.sources) == [[.garmin], [.appleHealth]])
        #expect(rows.map { $0.hrv(.sdnn) } == [nil, 61])
    }
}
