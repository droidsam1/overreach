import Domain
import Foundation
import Testing
import TodayPresentation

private actor QuickStore: CheckInRepository {
    private(set) var byDay: [CalendarDay: CheckIn] = [:]

    init(_ checkIns: [CheckIn] = []) {
        byDay = Dictionary(uniqueKeysWithValues: checkIns.map { ($0.day, $0) })
    }

    func checkIn(for day: CalendarDay) async throws -> CheckIn? { byDay[day] }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] {
        byDay.values.filter { range.contains($0.day) }.sorted { $0.day < $1.day }
    }
    func save(_ checkIn: CheckIn) async throws { byDay[checkIn.day] = checkIn }
}

private struct QuietMetrics: MetricsSource {
    let kind = DataSourceKind.appleHealth
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

@MainActor
@Suite("Quick check-in")
struct QuickCheckInTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    private func loadedModel(_ store: QuickStore) async -> TodayModel {
        let model = TodayModel(sources: [QuietMetrics()], checkIns: store, calendar: calendar)
        await model.load(now: now)
        return model
    }

    @Test func offersTheStoredScaleInOrder() async {
        let model = await loadedModel(QuickStore())

        #expect(model.quickCheckIn.map(\.value) == [1, 2, 3, 4, 5])
        #expect(model.quickCheckIn.map(\.name) == ["Exhausted", "Tired", "So-so", "Good", "Great"])
    }

    @Test func aNewAnswerIsSavedAndShown() async {
        let store = QuickStore()
        let model = await loadedModel(store)

        await model.answerQuickCheckIn(4, now: now)

        #expect(await store.byDay[today]?.energy == 4)
        #expect(model.checkIn?.energy == 4)
        #expect(!model.quickCheckInNeedsDetails)
    }

    @Test func answeringOverAnExistingCheckInKeepsTheOtherFields() async {
        let existing = CheckIn(day: today, isSick: false, energy: 3, soreness: 2, note: "Slept badly")
        let store = QuickStore([existing])
        let model = await loadedModel(store)

        await model.answerQuickCheckIn(5, now: now)

        let saved = await store.byDay[today]
        #expect(saved?.energy == 5)
        #expect(saved?.soreness == 2)
        #expect(saved?.note == "Slept badly")
    }

    @Test func theWorstAnswerAsksForDetails() async {
        let model = await loadedModel(QuickStore())

        await model.answerQuickCheckIn(1, now: now)
        #expect(model.quickCheckInNeedsDetails)

        await model.answerQuickCheckIn(4, now: now)
        #expect(!model.quickCheckInNeedsDetails)
    }

    @Test func theVerdictChangesAfterAnswering() async {
        let model = await loadedModel(QuickStore())
        await model.answerQuickCheckIn(4, now: now)
        #expect(model.readinessLevel == .green)

        await model.answerQuickCheckIn(1, now: now)
        #expect(model.readinessLevel != .green)
    }
}
