import Domain
import Foundation
import Testing
@testable import TodayPresentation

private struct StubSource: MetricsSource {
    let kind: DataSourceKind
    var available = true
    var shouldFail = false
    var configure: @Sendable (inout DailyMetrics) -> Void = { _ in }

    func isAvailable() async -> Bool { available }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        var metrics = DailyMetrics(day: range.upperBound, sources: [kind])
        configure(&metrics)
        return [metrics]
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

@MainActor
@Suite("TodayModel")
struct TodayModelTests {
    @Test func mergesSourcesInPriorityOrder() async {
        let garmin = StubSource(kind: .garmin) { $0.hrvNightlyAverageMs = 37; $0.restingHeartRate = 52 }
        let health = StubSource(kind: .appleHealth) { $0.restingHeartRate = 55; $0.sleepSeconds = 7 * 3600 }
        let model = TodayModel(sources: [garmin, health])

        await model.load()

        #expect(model.metrics?.hrvNightlyAverageMs == 37)
        #expect(model.metrics?.restingHeartRate == 52)
        #expect(model.metrics?.sleepSeconds == 25_200.0)  // 7 h
        #expect(model.failedSources.isEmpty)
    }

    @Test func aFailingSourceDoesNotHideTheOthers() async {
        let garmin = StubSource(kind: .garmin, shouldFail: true)
        let health = StubSource(kind: .appleHealth) { $0.restingHeartRate = 55 }
        let model = TodayModel(sources: [garmin, health])

        await model.load()

        #expect(model.metrics?.restingHeartRate == 55)
        #expect(model.failedSources == [.garmin])
    }

    @Test func noAvailableSourcesMeansNoMetrics() async {
        let model = TodayModel(sources: [StubSource(kind: .garmin, available: false)])

        await model.load()

        #expect(model.metrics == nil)
        #expect(model.readiness.level == .unknown)
    }

    @Test func readinessIsReadyToDisplay() {
        let model = TodayModel(sources: [])

        #expect(model.readinessLevel == .unknown)
        #expect(model.readinessTitle == "Unknown")
    }
}
