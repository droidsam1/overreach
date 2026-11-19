import Domain
import Foundation
import Testing
@testable import TodayPresentation

private struct StubSource: MetricsSource {
    let kind: DataSourceKind
    var available = true
    var shouldFail = false
    var accessFails = false
    var configure: @Sendable (inout DailyMetrics) -> Void = { _ in }

    func isAvailable() async -> Bool { available }

    func requestAccess() async throws {
        if accessFails { throw MissingEntitlement() }
    }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        var metrics = DailyMetrics(day: range.upperBound, sources: [kind])
        configure(&metrics)
        return [metrics]
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct MissingEntitlement: LocalizedError {
    var errorDescription: String? { "Missing com.apple.developer.healthkit entitlement." }
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

    @Test func aFailingSourceSaysWhy() async {
        let model = TodayModel(sources: [StubSource(kind: .appleHealth, shouldFail: true)])

        await model.load()

        #expect(model.showsSourceWarning)
        #expect(model.sourceWarningDetail == "Apple Health: \(URLError(.notConnectedToInternet).localizedDescription)")
    }

    @Test func aPermissionRequestThatCannotBeMadeIsShown() async {
        let model = TodayModel(sources: [StubSource(kind: .appleHealth, accessFails: true)])

        await model.connectHealth()

        #expect(model.accessError?.contains("Missing com.apple.developer.healthkit entitlement.") == true)
        #expect(model.accessError?.hasPrefix("Apple Health") == true)
    }

    @Test func aSuccessfulPermissionRequestShowsNoError() async {
        let model = TodayModel(sources: [StubSource(kind: .appleHealth)])

        await model.connectHealth()

        #expect(model.accessError == nil)
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
