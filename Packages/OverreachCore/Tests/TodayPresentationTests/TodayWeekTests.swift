import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

private actor WeekSource: MetricsSource {
    nonisolated let kind = DataSourceKind.appleHealth
    let days: [DailyMetrics]
    let activities: [RunActivity]
    private(set) var accessRequests = 0

    init(days: [DailyMetrics], activities: [RunActivity] = []) {
        self.days = days
        self.activities = activities
    }

    func isAvailable() async -> Bool { true }
    func requestAccess() async { accessRequests += 1 }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        activities.filter { (start...end).contains($0.startedAt) }
    }
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
        #expect(model.hrvCoverageNote == "Still building your usual HRV range (2 of 14 comparable readings needed).")
        #expect(model.showsReadinessDetails)
    }

    @Test func lowHRVShowsTheMeasuredDenominatorAndConfiguredWindow() async {
        let baseline = (6...25).map { day(-$0, sleepHours: nil, hrv: 55, steps: nil) }
        let recent = [0, -1, -3].map { day($0, sleepHours: nil, hrv: 35, steps: nil) }
        let model = TodayModel(
            sources: [WeekSource(days: baseline + recent)],
            readinessSettings: .init(rollingDays: 5), calendar: calendar
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessLines.map(\.text) == [
            "HRV below your usual range (3 of 3 comparable readings low in the last 5 days)."
        ])
        #expect(model.hrvCoverageNote == nil)
    }

    @Test func aMissingRecentReadingShowsWhyHRVWasSkipped() async {
        let baseline = (7...25).map { day(-$0, sleepHours: nil, hrv: 55, steps: nil) }
        let model = TodayModel(
            sources: [WeekSource(days: baseline + [day(-1, sleepHours: nil, hrv: 35, steps: nil)])], calendar: calendar
        )

        await model.load(now: now)

        #expect(model.readinessLevel == .unknown)
        #expect(model.showsReadinessCard)
        #expect(model.hrvCoverageNote == "Too few comparable HRV readings in the last 7 days (1 available, 3 needed).")
    }

    @Test func lowHRVExplainsTheComparisonWithoutInventingMissingNightsOrWorkouts() async {
        let days = (0...30).map { offset in
            let hrv: Double? = switch offset {
            case 0...3: 34
            case 4, 6: nil
            default: 43
            }
            var value = day(-offset, sleepHours: offset == 0 ? 7.6 : nil, hrv: hrv, steps: nil)
            value.restingHeartRate = offset == 0 ? 60 : 59
            return value
        }
        let model = TodayModel(sources: [WeekSource(days: days)], calendar: calendar,
                               format: Format(locale: Locale(identifier: "en_US")))
        await model.load(now: now)

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessSummary == "Your HRV is trending below your usual range.")
        #expect(model.readinessAdvice == "Keep it easy today. Run at a pace you can talk at, or lift with light effort.")
        #expect(model.readinessLines.first?.text.contains("4 of 5 comparable readings low") == true)
        #expect(model.readinessLines.first?.source?.absoluteString == "https://doi.org/10.3390/ijerph181910299")
        #expect(model.readinessContext.contains("Sleep last night was 7.6 h."))
        #expect(model.readinessContext.contains(
            "Resting heart rate today is 60 bpm. The average over 7 measured days in the last week is 59 bpm."
        ))
        #expect(model.readinessTrainingContext == nil)
    }

    @Test func showsOnlyWorkoutsFromTheDayBeforeTheLatestComparableReading() async throws {
        let days = (0...25).map { offset in
            day(-offset, sleepHours: nil, hrv: offset == 0 ? nil : (offset < 7 ? 32 : 50), steps: nil)
        }
        let older = RunActivity(id: "prior-workout", source: .appleHealth, name: "Intervals",
                                startedAt: days[2].day.startDate(in: calendar).addingTimeInterval(18 * 3_600),
                                durationSeconds: 1_800, distanceMeters: 4_000)
        let sameDay = RunActivity(id: "same-day", source: .appleHealth, name: "Not before the reading",
                                  startedAt: days[1].day.startDate(in: calendar).addingTimeInterval(18 * 3_600),
                                  durationSeconds: 1_800, distanceMeters: 4_000)
        let model = TodayModel(sources: [WeekSource(days: days, activities: [sameDay, older])], calendar: calendar)
        await model.load(now: now)

        let context = try #require(model.readinessTrainingContext)
        #expect(context.workouts.count == 1)
        #expect(context.workouts.first?.contains("Intervals") == true)
        #expect(model.readinessContext.contains("Resting heart rate is unavailable for today."))
        #expect(model.readinessContext.contains("Sleep data for last night is unavailable."))
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
        #expect(model.readinessAdvice == "Rest or go for a walk today.")
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
