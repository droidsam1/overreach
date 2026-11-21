import Domain
import Foundation
import GarminImport
import Testing

/// Fixtures have the exact shape of real Personal API responses (recorded 2026-11-20) with synthetic values.
private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
    CalendarDay(year: year, month: month, day: day)
}

private func utc(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

@Suite("Garmin decoding")
struct GarminDecodingTests {
    @Test func hrvNights() throws {
        let decoded = try GarminDecoding.hrvNights(from: fixture("hrv-daily-range"))

        #expect(decoded.records.count == 14)
        #expect(decoded.skipped == 0)
        let first = try #require(decoded.records.first)
        #expect(first.day == day(2025, 12, 26))
        #expect(first.lastNightAverage == 36)
        #expect(first.lastNight5MinuteHigh == 55)
        #expect(first.weeklyAverage == 37)
        #expect(first.baselineBalancedLow == 37)
        #expect(first.baselineBalancedUpper == 44)
        #expect(first.status == "UNBALANCED")
    }

    @Test func sleepRangeAndSingleNight() throws {
        let range = try GarminDecoding.sleeps(from: fixture("sleep-summaries-range"))
        let single = try GarminDecoding.sleeps(from: fixture("sleep-day"))

        #expect(range.records.count == 14)
        let first = try #require(range.records.first)
        #expect(first.day == day(2025, 12, 26))
        #expect(first.sleepSeconds == 22_497)
        #expect(first.deepSeconds == 4_208)
        #expect(first.lightSeconds == 16_160)
        #expect(first.remSeconds == 2_132)
        #expect(first.awakeSeconds == 2_076)
        #expect(first.score == 65)
        #expect(first.averageRespiration == 14.028)
        #expect(first.averageSpO2 == 89.78)
        #expect(first.end == Date(timeIntervalSince1970: 1_766_731_983))
        #expect(single.records.count == 1)
    }

    @Test func dailySummaries() throws {
        let decoded = try GarminDecoding.dailySummaries(from: fixture("daily-summaries-v2"))

        #expect(decoded.records.count == 14)
        let first = try #require(decoded.records.first)
        #expect(first.day == day(2025, 12, 26))
        #expect(first.restingHeartRate == 53)
        #expect(first.steps == 19_022)
        #expect(first.averageStress == 23)
        #expect(first.bodyBatteryHigh == 60)
        #expect(first.bodyBatteryLow == 11)
        #expect(first.averageRespiration == 14)
        #expect(first.averageSpO2 == 87)
    }

    @Test func vo2MaxOnlyOnDaysItChanged() throws {
        let decoded = try GarminDecoding.vo2Max(from: fixture("vo2max"))

        let days = [day(2025, 12, 15), day(2025, 12, 23), day(2025, 12, 25), day(2026, 1, 7)]
        #expect(decoded.records.map(\.day) == days)
        #expect(decoded.records.first?.value == 53.265)
    }

    @Test func activities() throws {
        let decoded = try GarminDecoding.activities(from: fixture("activities"))

        #expect(decoded.records.count == 13)
        let latest = try #require(decoded.records.first)
        #expect(latest.id == "10000001")
        #expect(latest.isStrength)
        let expectedStart = try utc("2026-01-08T13:02:55Z")
        #expect(latest.startedAt == expectedStart)
        #expect(latest.totalSets == 18)
        #expect(latest.totalReps == 121)
        #expect(decoded.records.filter(\.isRun).count == 4)
        #expect(decoded.records.filter(\.isStrength).count == 9)
    }

    @Test func noDataIsEmptyNotAnError() throws {
        #expect(try GarminDecoding.hrvNights(from: Data()).records.isEmpty)
        #expect(try GarminDecoding.sleeps(from: Data("  \n".utf8)).records.isEmpty)
        #expect(try GarminDecoding.dailySummaries(from: Data(#"{"data":[]}"#.utf8)).records.isEmpty)
    }

    @Test func aChangedShapeThrowsInsteadOfReturningNothing() throws {
        #expect(throws: GarminDecodingError.unexpectedShape("activities")) {
            try GarminDecoding.activities(from: fixture("not-found-404"))
        }
        #expect(throws: GarminDecodingError.unexpectedShape("hrv")) {
            try GarminDecoding.hrvNights(from: Data("<html>".utf8))
        }
    }

    @Test func oneUnreadableRecordOrFieldDoesNotDropTheRest() throws {
        let json = """
            {"hrvSummaries": [
              {"calendarDate": "2026-01-02", "lastNightAvg": "41", "lastNight5MinHigh": {"changed": true},
               "status": "NONE", "newField": [1, 2]},
              {"lastNightAvg": 50},
              "not an object",
              {"calendarDate": "2026-01-03", "lastNightAvg": 44.5, "status": "BALANCED"}
            ]}
            """
        let decoded = try GarminDecoding.hrvNights(from: Data(json.utf8))

        #expect(decoded.records.map(\.day) == [day(2026, 1, 2), day(2026, 1, 3)])
        #expect(decoded.records[0].lastNightAverage == 41)  // numeric string
        #expect(decoded.records[0].lastNight5MinuteHigh == nil)  // changed type: missing, not fatal
        #expect(decoded.records[0].status == nil)  // NONE is no status
        #expect(decoded.records[1].lastNightAverage == 44.5)
        #expect(decoded.skipped == 2)  // no date, not an object
    }

    @Test func notEnoughDataValuesAreMissing() throws {
        let json = """
            {"data": [{"calendarDate": "2026-01-02", "stress": {"avgLevel": -1}, "heartRate": {"restingValue": 0}}]}
            """
        let summary = try #require(try GarminDecoding.dailySummaries(from: Data(json.utf8)).records.first)

        #expect(summary.averageStress == nil)
        #expect(summary.restingHeartRate == nil)
    }
}

@Suite("Garmin mapping")
struct GarminMappingTests {
    @Test func dailyMetricsMergeEveryEndpointPerDay() throws {
        let metrics = GarminMapping.dailyMetrics(
            hrv: try GarminDecoding.hrvNights(from: fixture("hrv-daily-range")).records,
            sleep: try GarminDecoding.sleeps(from: fixture("sleep-summaries-range")).records,
            summaries: try GarminDecoding.dailySummaries(from: fixture("daily-summaries-v2")).records,
            vo2Max: try GarminDecoding.vo2Max(from: fixture("vo2max")).records
        )

        #expect(metrics.count == 17)  // 14 days of data plus three earlier VO2max days
        #expect(metrics.map(\.day) == metrics.map(\.day).sorted())
        let night = try #require(metrics.first { $0.day == day(2025, 12, 26) })
        #expect(night.hrvNightlyAverageMs == 36)
        #expect(night.hrvMetric == .rmssd)
        #expect(night.hrv(.rmssd) == 36 && night.hrv(.sdnn) == nil)
        #expect(night.hrvBaselineLowMs == 37)
        #expect(night.hrvBaselineHighMs == 44)
        #expect(night.hrvStatus == "UNBALANCED")
        #expect(night.sleepSeconds == 22_497)
        let interval = try #require(night.sleepInterval)
        #expect(interval.upperBound.timeIntervalSince(interval.lowerBound) >= 22_497)
        #expect(night.sleepScore == 65)
        #expect(night.restingHeartRate == 53)
        #expect(night.steps == 19_022)
        #expect(night.averageStress == 23)
        #expect(night.bodyBatteryHigh == 60)
        #expect(night.respirationRate == 14)  // the daily summary wins over the sleep record
        #expect(night.spo2Average == 87)
        #expect(night.sources == [.garmin])
        #expect(metrics.first { $0.day == day(2025, 12, 15) }?.vo2Max == 53.265)
    }

    @Test func daysWithoutValuesAreLeftOut() {
        let empty = GarminSleep(day: day(2026, 1, 1))
        let summary = GarminDailySummary(day: day(2026, 1, 2))

        #expect(GarminMapping.dailyMetrics(sleep: [empty], summaries: [summary]).isEmpty)
    }

    @Test func runsCarryGarminLoadAndTrainingEffect() throws {
        let activities = try GarminDecoding.activities(from: fixture("activities")).records
        let runs = GarminMapping.runs(activities)

        #expect(runs.map(\.id) == ["10000020", "10000018", "10000014", "10000004"])  // oldest first
        let first = try #require(runs.first)
        #expect(first.source == .garmin)
        let expectedStart = try utc("2025-12-15T17:25:07Z")
        #expect(first.startedAt == expectedStart)
        #expect(first.durationSeconds == 2_324.215)
        #expect(first.distanceMeters == 4_754.272)
        #expect(first.trainingLoad == 55.405)
        #expect(first.averageCadence == 101.35)
        #expect(first.elevationGainMeters == 41.5)
    }

    @Test func strengthRecordingsAreNotSessions() throws {
        let activities = try GarminDecoding.activities(from: fixture("activities")).records
        let strength = GarminMapping.strengthActivities(activities)

        #expect(strength.count == 9)
        let first = try #require(strength.first)
        #expect(first.id == "10000026")
        #expect(first.source == .garmin)
        #expect(first.totalSets == 13)
        #expect(first.totalReps == 85)
        #expect(first.trainingLoad != nil)
    }
}

@Suite("Garmin sync plan")
struct GarminSyncPlanTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    private let today = CalendarDay(year: 2026, month: 11, day: 20)

    @Test func firstSyncFetchesSixtyDays() {
        let range = GarminSyncPlan.range(lastSynced: nil, today: today, calendar: calendar)
        #expect(range == day(2026, 9, 22)...today)
    }

    @Test func laterSyncsRefetchTheLastDays() {
        let fresh = GarminSyncPlan.range(lastSynced: today, today: today, calendar: calendar)
        let days = GarminSyncPlan.range(lastSynced: day(2026, 11, 15), today: today, calendar: calendar)
        let longAgo = GarminSyncPlan.range(lastSynced: day(2025, 1, 1), today: today, calendar: calendar)

        #expect(fresh == day(2026, 11, 19)...today)
        #expect(days == day(2026, 11, 15)...today)
        #expect(longAgo == day(2026, 9, 22)...today)
    }

    @Test func rangesAreSplitToGarminsLimits() {
        let windows = GarminSyncPlan.windows(day(2026, 9, 22)...today, maximumDays: 31, calendar: calendar)

        #expect(windows == [
            day(2026, 9, 22)...day(2026, 10, 22),
            day(2026, 10, 23)...day(2026, 11, 20),
        ])
    }

    @Test func aFirstSyncIsAHandfulOfRequests() {
        let requests = GarminSyncPlan.requests(for: day(2026, 9, 22)...today, calendar: calendar)

        #expect(requests.count == 6)  // HRV, summaries, VO2max, activities: 1 each; sleep: 2
        #expect(requests.contains(.sleep(day(2026, 10, 23)...today)))
        #expect(requests.first?.path == "/hrv-service/hrv/daily/2026-09-22/2026-11-20")
        #expect(
            GarminEndpoint.activities(today...today, start: 40, limit: 40).path
                == "/activitylist-service/activities/search/activities?start=40&limit=40"
                + "&startDate=2026-11-20&endDate=2026-11-20"
        )
    }
}
