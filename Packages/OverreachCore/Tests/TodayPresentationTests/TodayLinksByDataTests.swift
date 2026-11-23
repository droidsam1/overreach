import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

private struct DataSource: MetricsSource {
    let kind = DataSourceKind.appleHealth
    var days: [DailyMetrics] = []
    var runList: [RunActivity] = []
    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runList }
}

@MainActor
@Suite("Today: links follow the data")
struct TodayLinksByDataTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .iso8601)

    private func reading(offset: Int) -> DailyMetrics {
        var metrics = DailyMetrics(
            day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar), sources: [.appleHealth]
        )
        metrics.sleepSeconds = 7 * 3_600
        return metrics
    }

    private func model(_ source: DataSource) -> TodayModel {
        TodayModel(sources: [source], calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))
    }

    @Test func withNoDataThereAreNoLinks() async {
        let model = model(DataSource())
        await model.load(now: now)
        #expect(model.links.isEmpty)
        #expect(!model.visibleBlocks.contains(.linkRow))
    }

    @Test func aReadingUnlocksWhyAndRecoveryOnly() async {
        let model = model(DataSource(days: [reading(offset: 0)]))
        await model.load(now: now)
        #expect(model.links.contains(.recovery) && !model.links.contains(.history))
    }

    @Test func aRunUnlocksHistory() async {
        let run = RunActivity(
            id: "r", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let model = model(DataSource(runList: [run]))
        await model.load(now: now)
        #expect(model.links.contains(.history) && !model.links.contains(.recovery))
    }

    @Test func readingsAndARunUnlockEveryLink() async {
        let run = RunActivity(
            id: "r", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let model = model(DataSource(days: (0..<10).map { reading(offset: -$0) }, runList: [run]))
        await model.load(now: now)
        #expect(model.links.first == .why)
        #expect(model.links.suffix(2) == [.recovery, .history])
    }
}
