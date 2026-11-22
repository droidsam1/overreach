import Domain
import Fixtures
import Foundation
import Testing
import TodayPresentation

private actor SickDay: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct SickCheckIn: CheckInRepository {
    let day: CalendarDay
    func checkIn(for day: CalendarDay) async throws -> CheckIn? { day == self.day ? CheckIn(day: day, isSick: true) : nil }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { [] }
    func save(_ checkIn: CheckIn) async throws {}
}

@MainActor
@Suite("Rest day on Today")
struct RestDayTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func loadedModel(store: TestStore) async -> TodayModel {
        let today = CalendarDay(now, calendar: calendar)
        let model = TodayModel(
            sources: [SickDay()], checkIns: SickCheckIn(day: today), profiles: store, workouts: store, calendar: calendar
        )
        await model.load(now: now)
        return model
    }

    @Test func restRecommendedOffersRestAsThePrimaryAction() async {
        let model = await loadedModel(store: TestStore())
        #expect(model.nextAction == .rest)
        #expect(model.primaryActionTitle() == "Rest today")
        #expect(!model.restLoggedToday)
    }

    @Test func loggingRestShowsACalmDoneStateAndKeepsTheDay() async throws {
        let store = TestStore()
        let model = await loadedModel(store: store)

        await model.logRest(now: now)

        #expect(model.restLoggedToday)
        #expect(model.nextAction == .restLogged)
        #expect(model.heroTitle == "Rest logged. Recovery is training too.")
        #expect(model.primaryActionTitle() == "Undo rest")
        let today = CalendarDay(now, calendar: calendar)
        #expect(try await store.profile().restDays == [today])

        let reloaded = await loadedModel(store: store)
        #expect(reloaded.nextAction == .restLogged)
    }

    @Test func undoReturnsToTheRestAction() async throws {
        let store = TestStore()
        let model = await loadedModel(store: store)
        await model.logRest(now: now)

        await model.undoRest(now: now)

        #expect(!model.restLoggedToday)
        #expect(model.nextAction == .rest)
        #expect(try await store.profile().restDays.isEmpty)
    }

    @Test func loggingTwiceStoresTheDayOnce() async throws {
        let store = TestStore()
        let model = await loadedModel(store: store)
        await model.logRest(now: now)
        await model.logRest(now: now)
        #expect(try await store.profile().restDays.count == 1)
    }

    @Test func profilesWithoutRestDaysStillDecode() throws {
        let json = #"{"cycleTracking":"off","declaredBlocks":[],"deloads":[]}"#
        let profile = try JSONDecoder().decode(AthleteProfile.self, from: Data(json.utf8))
        #expect(profile.restDays.isEmpty)
        let day = CalendarDay(year: 2026, month: 11, day: 22)
        var updated = profile
        updated.logRest(on: day)
        let decoded = try JSONDecoder().decode(AthleteProfile.self, from: JSONEncoder().encode(updated))
        #expect(decoded.restDays == [day])
    }
}
