import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

private struct BudgetSource: MetricsSource {
    let kind = DataSourceKind.garmin
    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        range.upperBound.days(back: 28, through: range.upperBound).map { day in
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.steps = 9_000
            return metrics
        }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private extension CalendarDay {
    func days(back count: Int, through end: CalendarDay) -> [CalendarDay] {
        let calendar = Calendar(identifier: .iso8601)
        return (0...count).map { end.adding(days: -$0, calendar: calendar) }
    }
}

@MainActor
@Suite("Today: block budget")
struct TodayBlockBudgetTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .iso8601)

    private func model(sources: [any MetricsSource]) -> TodayModel {
        TodayModel(sources: sources, calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))
    }

    @Test func showsOnlyTheHeroWhileLoading() {
        let model = model(sources: [])
        #expect(model.visibleBlocks == [.hero])
        #expect(model.links.isEmpty)
    }

    @Test func neverExceedsTheBudget() async {
        for sources in [[], [BudgetSource()]] as [[any MetricsSource]] {
            let model = model(sources: sources)
            await model.load(now: now)
            #expect(model.visibleBlocks.count <= TodayModel.blockBudget)
            #expect(TodayModel.blockBudget == 4)
        }
    }

    @Test func linkRowKeepsWhyRecoveryAndHistoryInOrder() async {
        let model = model(sources: [BudgetSource()])
        await model.load(now: now)
        let links = model.links
        #expect(links.first == .why)
        #expect(links.suffix(2) == [.recovery, .history])
        #expect(model.visibleBlocks.contains(.linkRow))
    }

    @Test func heroComesFirstAndPromptBeforeLinks() async {
        let model = model(sources: [BudgetSource()])
        await model.load(now: now)
        let blocks = model.visibleBlocks
        #expect(blocks.first == .hero)
        if let prompt = blocks.firstIndex(of: .pendingPrompt), let links = blocks.firstIndex(of: .linkRow) {
            #expect(prompt < links)
        }
    }
}
