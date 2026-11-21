import Analytics
import Domain
import Foundation
import Testing

/// Provenance, coverage, recency and outcome of each readiness input (ADR-0032).
@Suite("Readiness input audit")
struct ReadinessInputAuditTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(year: 2026, month: 11, day: 19) }
    private let wobble: [Double] = [0, 4, -3, 6, -5, 2, -1, 5, -4, 3]

    private func day(_ offset: Int, sources: Set<DataSourceKind>) -> DailyMetrics {
        DailyMetrics(day: today.adding(days: -offset, calendar: calendar), sources: sources)
    }

    /// Apple Health nights: SDNN around 55 ms from sleep readings, resting HR around 50 bpm, 7.5 h of sleep.
    private func appleNights(_ offsets: ClosedRange<Int> = 0...60) -> [DailyMetrics] {
        offsets.map { offset in
            var metrics = day(offset, sources: [.appleHealth])
            metrics.hrvSDNNMs = 55 + wobble[offset % wobble.count]
            metrics.hrvSDNNWindow = .sleep
            metrics.restingHeartRate = 50 + wobble[offset % wobble.count] / 5
            metrics.sleepSeconds = 7.5 * 3_600
            return metrics
        }
    }

    /// Garmin nights: whole-night RMSSD around 36 ms.
    private func garminNights(_ offsets: ClosedRange<Int> = 0...60) -> [DailyMetrics] {
        offsets.map { offset in
            var metrics = day(offset, sources: [.garmin])
            metrics.hrvRMSSDMs = 36 + wobble[offset % wobble.count] / 2
            metrics.restingHeartRate = 48 + wobble[offset % wobble.count] / 5
            metrics.sleepSeconds = 7 * 3_600
            return metrics
        }
    }

    /// Merges per day, Garmin first, as Today does.
    private func merged(_ garmin: [DailyMetrics], _ health: [DailyMetrics]) -> [DailyMetrics] {
        var byDay: [CalendarDay: DailyMetrics] = [:]
        for metrics in garmin + health {
            byDay[metrics.day] = (byDay[metrics.day] ?? DailyMetrics(day: metrics.day)).merging(metrics)
        }
        return Array(byDay.values)
    }

    private func readiness(_ history: [DailyMetrics], checkIn: CheckIn? = nil) -> Readiness {
        ReadinessRules.readiness(today: today, history: history, checkIn: checkIn, calendar: calendar)
    }

    @Test func garminRMSSDAndAppleSDNNTogetherRecordWhichSeriesWasJudgedAndWhereEachInputCameFrom() throws {
        let result = readiness(merged(garminNights(), appleNights()))

        #expect(result.inputs.map(\.input) == [
            .hrv(HRVSeriesID(.rmssd, .sleep)), .hrv(HRVSeriesID(.sdnn, .sleep)), .restingHeartRate, .sleep, .checkIn,
        ])
        let hrv = try #require(result.hrvInput)
        #expect(hrv.status == .compared && hrv.source == .garmin && hrv.outcome == .within)
        #expect(hrv.latestDay == today && hrv.recentDays == 7 && hrv.recentReadings == 7)
        #expect(hrv.reference?.kind == .personalBaseline)
        #expect(hrv.reference?.days == 60 && hrv.reference?.readings == 60 && hrv.reference?.minimumReadings == 14)
        // The baseline keeps the six earlier nights of the recent window (ADR-0032).
        #expect(hrv.reference?.overlappingReadings == 6)
        #expect(result.inputs[1].status == .anotherSeriesUsed && result.inputs[1].source == .appleHealth)

        // Garmin's resting HR and sleep win the merge; their provenance survives it.
        let resting = try #require(result.input(.restingHeartRate))
        #expect(resting.status == .compared && resting.source == .garmin && resting.outcome == .within)
        #expect(resting.value == 48 && resting.reference?.readings == 60)
        let sleep = try #require(result.input(.sleep))
        #expect(sleep.source == .garmin && sleep.value == 7 && sleep.outcome == .within)
        #expect(sleep.reference?.kind == .fixedThreshold && sleep.reference?.value == 6)
    }

    @Test func implausibleReadingsAreIgnoredAndLeaveTheMeasuredDenominator() throws {
        var days = appleNights()
        // A low week with two broken readings among the seven nights: zero and an artefact.
        for (offset, value) in [44.0, 0, 43, 900, 45, 44, 46].enumerated() {
            days[offset].hrvSDNNMs = value
        }

        let result = readiness(days)

        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 5)))
        #expect(result.hrvCoverage?.recentReadings == 5)
        let hrv = try #require(result.hrvInput)
        #expect(hrv.recentReadings == 5 && hrv.rejectedReadings == 2 && hrv.outcome == .below)
    }

    @Test func sparseNightsCountOnlyWhatWasMeasured() throws {
        // A watch worn every third night: 20 baseline readings, 3 in the last week.
        let days = appleNights().filter { calendarOffset($0.day) % 3 == 0 }

        let result = readiness(days)
        let hrv = try #require(result.hrvInput)

        #expect(hrv.status == .compared && hrv.recentReadings == 3 && hrv.reference?.readings == 20)
        #expect(hrv.reference?.overlappingReadings == 2)
    }

    @Test func aDeviceSwitchKeepsTheOldSeriesAsStaleAndBuildsTheNewOne() throws {
        // Garmin RMSSD until ten days ago, then an Apple Watch for the last nine nights.
        let result = readiness(garminNights(10...60) + appleNights(0...8))

        #expect(result.level != .red && !result.reasons.contains(.hrvBelowBaseline(nights: 7)))
        let new = try #require(result.hrvInput)
        #expect(new.input == .hrv(HRVSeriesID(.sdnn, .sleep)))
        #expect(new.status == .buildingBaseline && new.reference?.readings == 8)
        let old = try #require(result.input(.hrv(HRVSeriesID(.rmssd, .sleep))))
        #expect(old.status == .stale && old.source == .garmin)
        #expect(old.latestDay == today.adding(days: -10, calendar: calendar))
    }

    @Test func daytimeFallbackReadingsAreTheirOwnSeries() throws {
        // Sleep tracking stopped a week ago: Apple Health now averages the day's readings, which run lower.
        var days = appleNights()
        for offset in 0...6 {
            days[offset].hrvSDNNMs = 38
            days[offset].hrvSDNNWindow = .daytime
            days[offset].sleepSeconds = nil
        }

        let result = readiness(days)

        #expect(!result.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } })
        let daytime = try #require(result.hrvInput)
        #expect(daytime.input == .hrv(HRVSeriesID(.sdnn, .daytime)))
        #expect(daytime.status == .buildingBaseline && daytime.reference?.readings == 6)
        #expect(result.hrvCoverage?.window == .daytime)
        let night = try #require(result.input(.hrv(HRVSeriesID(.sdnn, .sleep))))
        #expect(night.status == .stale && night.latestDay == today.adding(days: -7, calendar: calendar))
        #expect(result.input(.sleep)?.status == .missing)  // no sleep in the recent window
    }

    @Test func aSourceOutageFallsBackToTheOtherSeriesAndSaysSo() throws {
        // Garmin has not synced for nine days; the Apple Watch kept recording.
        let result = readiness(merged(garminNights(9...60), appleNights()))

        let hrv = try #require(result.hrvInput)
        #expect(hrv.input == .hrv(HRVSeriesID(.sdnn, .sleep)) && hrv.status == .compared)
        let garmin = try #require(result.input(.hrv(HRVSeriesID(.rmssd, .sleep))))
        #expect(garmin.status == .stale && garmin.latestDay == today.adding(days: -9, calendar: calendar))
        #expect(result.input(.restingHeartRate)?.source == .appleHealth)
    }

    @Test func noDataTodayMarksTodaysInputsStaleWithoutInventingThem() throws {
        let result = readiness(appleNights(1...60))

        #expect(result.hrvInput?.status == .compared)
        #expect(result.hrvInput?.latestDay == today.adding(days: -1, calendar: calendar))
        let resting = try #require(result.input(.restingHeartRate))
        #expect(resting.status == .stale && resting.value == nil && resting.outcome == nil)
        #expect(resting.latestDay == today.adding(days: -1, calendar: calendar))
        #expect(result.input(.sleep)?.status == .stale)
        #expect(!result.reasons.contains { if case .shortSleep = $0 { true } else { false } })
    }

    @Test func anImplausibleRestingHeartRateOrSleepIsIgnored() throws {
        var days = appleNights()
        days[0].restingHeartRate = 220
        days[0].sleepSeconds = 0

        let result = readiness(days)

        #expect(result.level == .green && result.reasons.isEmpty)
        #expect(result.input(.restingHeartRate)?.status == .outOfRange)
        #expect(result.input(.restingHeartRate)?.rejectedReadings == 1)
        #expect(result.input(.sleep)?.status == .outOfRange)
    }

    @Test func anOldCheckInIsReportedAsStaleAndNeverAnswersForToday() throws {
        let yesterday = today.adding(days: -1, calendar: calendar)
        let result = readiness(appleNights(), checkIn: CheckIn(day: yesterday, isSick: true, energy: 1))

        #expect(result.level == .green)
        let checkIn = try #require(result.input(.checkIn))
        #expect(checkIn.status == .stale && checkIn.latestDay == yesterday && checkIn.source == .manual)
    }

    @Test func aSickCheckInKeepsTheAuditOfTheOtherInputs() {
        let result = readiness(appleNights(), checkIn: CheckIn(day: today, isSick: true))

        #expect(result.reasons == [.markedSick])
        #expect(result.hrvInput?.status == .compared)
        #expect(result.input(.checkIn)?.status == .compared)
    }

    // MARK: - Stored data

    @Test func dailyMetricsWrittenBeforeTheAuditDecodeWithTheirSourceAndAsSleepReadings() throws {
        let json = #"{"day":{"year":2026,"month":11,"day":19},"hrvSDNNMs":52,"restingHeartRate":51,"#
            + #""sleepSeconds":27000,"sources":["appleHealth"]}"#
        let metrics = try JSONDecoder().decode(DailyMetrics.self, from: Data(json.utf8))

        #expect(metrics.hrvWindow(.sdnn) == .sleep)
        #expect(metrics.restingHeartRateOrigin == .appleHealth && metrics.sleepOrigin == .appleHealth)
        let roundTrip = try JSONDecoder().decode(DailyMetrics.self, from: JSONEncoder().encode(metrics))
        #expect(roundTrip == metrics)
    }

    @Test func readinessWrittenBeforeTheAuditDecodesWithoutInputs() throws {
        let json = #"""
        {"level":"amber","reasons":[],"hrvCoverage":{"metric":"rmssd",
        "latestDay":{"year":2026,"month":11,"day":19},"recentDays":7,"recentReadings":5,"minimumRecentReadings":3,
        "baselineDays":60,"baselineReadings":30,"minimumBaselineReadings":14}}
        """#
        let readiness = try JSONDecoder().decode(Readiness.self, from: Data(json.utf8))

        #expect(readiness.inputs.isEmpty && readiness.hrvInput == nil)
        #expect(readiness.hrvCoverage?.window == nil && readiness.hrvCoverage?.canCompare == true)
        let audited = self.readiness(appleNights())
        #expect(try JSONDecoder().decode(Readiness.self, from: JSONEncoder().encode(audited)) == audited)
    }

    private func calendarOffset(_ day: CalendarDay) -> Int {
        calendar.dateComponents([.day], from: day.startDate(in: calendar), to: today.startDate(in: calendar)).day ?? 0
    }
}
