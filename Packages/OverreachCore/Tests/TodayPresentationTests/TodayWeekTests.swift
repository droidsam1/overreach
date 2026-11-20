import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

private actor WeekSource: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    let days: [DailyMetrics]
    private(set) var accessRequests = 0

    init(days: [DailyMetrics]) { self.days = days }

    func isAvailable() async -> Bool { true }
    func requestAccess() async { accessRequests += 1 }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct OneCheckIn: CheckInRepository {
    let stored: CheckIn
    func checkIn(for day: CalendarDay) async throws -> CheckIn? { day == stored.day ? stored : nil }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] { [] }
    func save(_ checkIn: CheckIn) async throws {}
}

@MainActor
@Suite("Today with a week of data")
struct TodayWeekTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, sleepHours: Double?, hrv: Double?, steps: Int?) -> DailyMetrics {
        var metrics = DailyMetrics(day: CalendarDay(now, calendar: calendar).adding(days: offset, calendar: calendar),
                                   sources: [.appleHealth])
        metrics.sleepSeconds = sleepHours.map { $0 * 3_600 }
        metrics.hrvNightlyAverageMs = hrv
        metrics.steps = steps
        return metrics
    }

    @Test func todayShowsItsValuesAndTheWeekAverages() async throws {
        var today = day(0, sleepHours: 7, hrv: 50, steps: 9_000)
        today.deepSleepSeconds = 1.2 * 3_600
        today.remSleepSeconds = 1.5 * 3_600
        let source = WeekSource(days: [day(-8, sleepHours: 2, hrv: 10, steps: 100), day(-2, sleepHours: 6, hrv: 40, steps: 7_000), today])
        let model = TodayModel(sources: [source], calendar: calendar, format: Format(locale: Locale(identifier: "en_US")))

        await model.load(now: now)

        #expect(model.sleepHours == 7)
        #expect(model.steps == 9_000)
        #expect(model.week.count == 2)  // eight days ago is out of the week
        #expect(model.sleepCaption == "Deep 1.2 h · REM 1.5 h")
        #expect(model.hrvCaption == "7-day avg 45 ms")
        #expect(model.stepsCaption == "7-day avg 8,000")
        #expect(model.sourcesText == "From Apple Health")
        #expect(!model.showsBodyBattery)
        #expect(!model.showsConnectHealth)
    }

    @Test func connectingAsksForAccessAndReloads() async {
        let source = WeekSource(days: [])
        let model = TodayModel(sources: [source], calendar: calendar)
        await model.load(now: now)
        #expect(model.showsConnectHealth)

        await model.connectHealth(now: now)
        #expect(await source.accessRequests == 1)
    }

    @Test func todaysCheckInFeedsTheReadinessLight() async {
        let todayKey = CalendarDay(now, calendar: calendar)
        let checkIns = OneCheckIn(stored: CheckIn(day: todayKey, isSick: true))
        let model = TodayModel(sources: [WeekSource(days: [])], checkIns: checkIns, calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .red)
        #expect(model.readinessAdvice == "Make it a recovery day: a walk or a very easy session. If you lift, keep it light (RPE 6 or less).")
        #expect(
            model.readinessLines.map(\.text) == ["Marked as sick in today's check-in. Rest until the symptoms ease."]
        )
        #expect(model.readinessLines.first?.evidence == EvidenceLevel.limited.displayName)
    }

    @Test func shortSleepExplainsTheAmberLight() async {
        let model = TodayModel(
            sources: [WeekSource(days: [day(0, sleepHours: 5, hrv: nil, steps: nil)])], calendar: calendar,
            format: Format(locale: Locale(identifier: "en_US"))
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessLines.map(\.text) == ["Short sleep: 5 h."])
        #expect(model.readinessLines.map(\.evidence) == [EvidenceLevel.moderate.displayName])
    }

    @Test func withoutDataTheLightSaysWhatItNeeds() async {
        let model = TodayModel(sources: [WeekSource(days: [])], calendar: calendar)

        await model.load(now: now)

        #expect(model.readinessLevel == .unknown)
        #expect(model.readinessAdvice == "Not enough data yet to judge today.")
        #expect(model.readinessLines.count == 1)
    }
}
