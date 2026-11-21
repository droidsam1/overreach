import Analytics
import Domain
import Foundation
import Testing

@Suite("Readiness rules")
struct ReadinessRulesTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(year: 2026, month: 11, day: 19) }

    /// A realistic history from Apple Health: nightly SDNN around 55 ms (± ~5), resting HR around 50 bpm, 7.5 h of sleep.
    private func history(
        days: Int = 60, recentHRV: [Double]? = nil, todayResting: Double? = nil, todaySleepHours: Double? = 7.5
    ) -> [DailyMetrics] {
        let wobble: [Double] = [0, 4, -3, 6, -5, 2, -1, 5, -4, 3]
        return (0...days).map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.appleHealth])
            metrics.hrvSDNNMs = 55 + wobble[offset % wobble.count]
            metrics.restingHeartRate = 50 + wobble[offset % wobble.count] / 5
            metrics.sleepSeconds = 7.5 * 3_600
            if let recentHRV, offset < recentHRV.count { metrics.hrvSDNNMs = recentHRV[offset] }
            if offset == 0 {
                if let todayResting { metrics.restingHeartRate = todayResting }
                metrics.sleepSeconds = todaySleepHours.map { $0 * 3_600 }
            }
            return metrics
        }
    }

    private func readiness(_ history: [DailyMetrics], checkIn: CheckIn? = nil) -> Readiness {
        ReadinessRules.readiness(today: today, history: history, checkIn: checkIn, calendar: calendar)
    }

    @Test func aNormalDayIsGreen() {
        let result = readiness(history())
        #expect(result.level == .green)
        #expect(result.reasons.isEmpty)
        #expect(result.hrvCoverage?.canCompare == true)
    }

    @Test func noDataIsUnknown() {
        let result = readiness([])
        #expect(result.level == .unknown && result.reasons == [.missingData])
        #expect(result.hrvInput?.status == .missing)
        #expect(result.input(.restingHeartRate)?.status == .missing)
        #expect(result.input(.sleep)?.status == .missing)
        #expect(result.input(.checkIn)?.status == .missing)
    }

    @Test func aFewDaysOfHistoryAreNotEnoughForABaseline() {
        let short = history(days: 5, todaySleepHours: nil)

        #expect(readiness(short).level == .unknown)
    }

    @Test func aWeekOfLowHRVTurnsAmber() {
        let result = readiness(history(recentHRV: [44, 46, 43, 47, 45, 52, 48]))

        #expect(result.level == .amber)
        #expect(result.reasons == [.hrvBelowBaseline(nights: 7)])
        #expect(result.hrvCoverage?.recentReadings == 7)
    }

    @Test func oneLowNightInsideANormalWeekStaysGreen() {
        #expect(readiness(history(recentHRV: [45, 57, 58, 56, 57, 55, 58])).level == .green)
    }

    @Test func HRVNeedsThreeRecentNights() {
        var days = history(recentHRV: [40, 41])
        for index in days.indices where (2..<7).contains(index) { days[index].hrvSDNNMs = nil }

        let result = readiness(days)
        #expect(result.level == .green)
        #expect(result.hrvCoverage?.recentReadings == 2)
        #expect(result.hrvCoverage?.canCompare == false)
    }

    @Test func invalidAndDifferentStatisticReadingsDoNotCountTowardCoverage() {
        var days = switchedToGarmin(garminNights: 30)
        days[0].hrvRMSSDMs = .infinity
        days[1].hrvRMSSDMs = 24
        days[2].hrvRMSSDMs = 24
        days[3].hrvRMSSDMs = nil
        days[4].hrvRMSSDMs = 0
        days[5].hrvRMSSDMs = 24
        days[6].hrvSDNNMs = days[6].hrvRMSSDMs  // one night read as SDNN instead: a different series
        days[6].hrvRMSSDMs = nil

        let result = readiness(days)
        #expect(result.reasons == [.hrvBelowBaseline(nights: 3)])
        #expect(result.hrvCoverage?.metric == .rmssd)
        #expect(result.hrvCoverage?.latestDay == days[1].day)
        #expect(result.hrvCoverage?.recentDays == 7)
        #expect(result.hrvCoverage?.recentReadings == 3)
        #expect(result.hrvCoverage?.baselineDays == 60)
        #expect(result.hrvCoverage?.baselineReadings == 26)
    }

    @Test func elevatedRestingHeartRateTurnsAmber() {
        let result = readiness(history(todayResting: 57))

        #expect(result.level == .amber)
        guard case .restingHeartRateElevated(let rise) = result.reasons.first else {
            Issue.record("Expected a resting HR reason")
            return
        }
        #expect(rise > 6 && rise < 8)
    }

    @Test func lowHRVAndHighRestingHeartRateTogetherAreRed() {
        let result = readiness(history(recentHRV: [42, 44, 43, 45, 44, 46, 45], todayResting: 58))

        #expect(result.level == .red)
        #expect(result.reasons.count == 2)
    }

    @Test func shortSleepAloneIsAmber() {
        let result = readiness(history(todaySleepHours: 5))

        #expect(result.level == .amber)
        #expect(result.reasons == [.shortSleep(hours: 5)])
    }

    @Test func subjectiveSignalsWithoutPhysiologyStayAmber() {
        let checkIn = CheckIn(day: today, energy: 1, soreness: 3)

        let result = readiness(history(todaySleepHours: 5), checkIn: checkIn)

        #expect(result.level == .amber)
        #expect(result.reasons == [.shortSleep(hours: 5), .lowEnergy(score: 1), .highSoreness(score: 3)])
    }

    @Test func sickIsRedWhateverTheNumbersSay() {
        let result = readiness(history(), checkIn: CheckIn(day: today, isSick: true))

        #expect(result.level == .red && result.reasons == [.markedSick])
    }

    @Test func aCheckInAloneIsEnoughToJudge() {
        #expect(readiness([], checkIn: CheckIn(day: today, energy: 4, soreness: 1)).level == .green)
    }

    @Test func reportedSymptomsTakePriorityAndApplyOnlyToTheirOwnDay() {
        let response = CheckIn.Context(question: .symptoms, answer: .yes)
        #expect(readiness([], checkIn: CheckIn(day: today, context: response)).reasons == [.symptomsLimitTraining])
        let yesterday = today.adding(days: -1, calendar: calendar)
        #expect(readiness([], checkIn: CheckIn(day: yesterday, isSick: true, context: response)).level == .unknown)
    }

    @Test(arguments: [CheckIn.Context.Answer.no, .unsure, .skipped])
    func anInconclusiveContextAnswerAloneCannotGiveAGreenLight(answer: CheckIn.Context.Answer) {
        let context = CheckIn.Context(question: .symptoms, answer: answer)
        #expect(readiness([], checkIn: CheckIn(day: today, context: context)).level == .unknown)
    }

    @Test func everyReasonCitesItsEvidence() {
        let reasons: [ReadinessReason] = [
            .markedSick, .hrvBelowBaseline(nights: 3), .hrvMayReflectCycle, .restingHeartRateElevated(bpmAboveBaseline: 6),
            .shortSleep(hours: 5), .lowEnergy(score: 1), .highSoreness(score: 3), .missingData,
            .phaseBaseline(window: .luteal, cycles: 2), .possibleLutealShift,
        ]
        let keys = reasons.map { ReadinessRules.evidence(for: $0).key }

        #expect(keys == [
            "illness-return", "readiness-hrv", "hrv-cycle-phase", "readiness-resting-hr", "readiness-sleep", "readiness-subjective",
            "readiness-subjective", "readiness-combination",
            "cycle-phase-baselines", "cycle-phase-baselines",
        ])
    }

    // MARK: HRV series (ADR-0024, ADR-0025)

    /// 60 nights of Apple Watch SDNN around 55 ms, then the last `garminNights` from a Garmin (RMSSD around 35 ms:
    /// a lower number for the same physiology).
    private func switchedToGarmin(garminNights: Int) -> [DailyMetrics] {
        history(todaySleepHours: nil).map { day in
            var day = day
            day.restingHeartRate = nil
            let offset = calendar.dateComponents(
                [.day], from: day.day.startDate(in: calendar), to: today.startDate(in: calendar)
            ).day ?? 0
            if offset < garminNights {
                day.hrvRMSSDMs = 35 + Double(offset % 3)
                day.hrvSDNNMs = nil  // the Apple Watch is no longer worn
                day.sources = [.garmin]
            }
            return day
        }
    }

    @Test func aNewWatchDoesNotLookLikeAnHRVDrop() {
        // A week of Garmin RMSSD against an SDNN baseline would read as "far below normal". It is not compared.
        let result = readiness(switchedToGarmin(garminNights: 7))

        #expect(!result.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } })
        #expect(result.level == .unknown)  // no RMSSD baseline yet, nothing else to judge
        #expect(result.hrvCoverage?.baselineReadings == 6)
        #expect(result.hrvCoverage?.minimumBaselineReadings == 14)
    }

    @Test func onceTheNewWatchHasABaselineItIsJudgedAgainstItsOwnNights() {
        var days = switchedToGarmin(garminNights: 30)
        for index in days.indices where days[index].hrvRMSSDMs != nil {
            let offset = calendar.dateComponents(
                [.day], from: days[index].day.startDate(in: calendar), to: today.startDate(in: calendar)
            ).day ?? 0
            if offset < 7 { days[index].hrvRMSSDMs = 26 }  // a real drop in RMSSD
        }

        let result = readiness(days)

        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 7)))
    }

    @Test func mergingKeepsBothStatisticsOfANight() {
        var garmin = DailyMetrics(day: today, sources: [.garmin])
        garmin.sleepScore = 80
        var health = DailyMetrics(day: today, sources: [.appleHealth])
        health.hrvSDNNMs = 50

        let merged = garmin.merging(health)  // Garmin has no HRV tonight: only the SDNN series has a value
        #expect(merged.hrv(.sdnn) == 50 && merged.hrv(.rmssd) == nil)
        #expect(merged.hrvNightlyAverageMs == 50 && merged.hrvMetric == .sdnn)

        garmin.hrvRMSSDMs = 38
        let both = garmin.merging(health)  // neither value replaces the other
        #expect(both.hrv(.rmssd) == 38 && both.hrv(.sdnn) == 50)
        #expect(both.hrvNightlyAverageMs == 38 && both.hrvMetric == .rmssd)
        #expect(health.merging(garmin) == both)  // the order of sources no longer decides which HRV survives
    }

    /// Someone wearing both watches: 60 nights of Apple SDNN around 55 ms (from `history`) and Garmin RMSSD around
    /// 35 ms on the last `garminNights`.
    private func wearingBoth(garminNights: Int, recentRMSSD: [Double] = [], recentSDNN: [Double] = []) -> [DailyMetrics] {
        history(recentHRV: recentSDNN.isEmpty ? nil : recentSDNN, todaySleepHours: nil).map { day in
            var day = day
            day.restingHeartRate = nil
            let offset = calendar.dateComponents(
                [.day], from: day.day.startDate(in: calendar), to: today.startDate(in: calendar)
            ).day ?? 0
            if offset < garminNights {
                day.hrvRMSSDMs = offset < recentRMSSD.count ? recentRMSSD[offset] : 35 + Double(offset % 3)
                day.sources.insert(.garmin)
            }
            return day
        }
    }

    @Test func withBothSeriesRMSSDIsJudgedAndSDNNIsNotMixedIn() {
        // Apple's SDNN drops this week, Garmin's RMSSD does not: only RMSSD is judged.
        let result = readiness(wearingBoth(garminNights: 60, recentSDNN: [40, 41, 39, 42, 40, 41, 40]))

        #expect(result.level == .green)
        #expect(result.hrvCoverage?.metric == .rmssd)
        #expect(result.hrvCoverage?.baselineReadings == 59)
    }

    @Test func aDropInTheChosenSeriesIsReportedWithItsStatistic() {
        let result = readiness(wearingBoth(garminNights: 60, recentRMSSD: [26, 27, 25, 28, 26, 27, 26]))

        #expect(result.reasons == [.hrvBelowBaseline(nights: 7)])
        #expect(result.hrvCoverage?.metric == .rmssd)
    }

    @Test func whileTheRMSSDBaselineBuildsTheSDNNSeriesKeepsBeingJudged() {
        // Garmin connected four nights ago without history: its RMSSD cannot be compared yet, the SDNN series can.
        let result = readiness(wearingBoth(garminNights: 4, recentSDNN: [44, 46, 43, 47, 45, 52, 48]))

        #expect(result.reasons == [.hrvBelowBaseline(nights: 7)])
        #expect(result.hrvCoverage?.metric == .sdnn)
        #expect(result.hrvCoverage?.baselineReadings == 60)
    }

    @Test func whenNoSeriesCanBeComparedTheCoverageIsTheWatchReadMostRecently() {
        // The Apple Watch last read SDNN four nights ago; the Garmin has read RMSSD for the last three nights.
        var days = switchedToGarmin(garminNights: 3)
        for index in [3, 5, 6] { days[index].hrvSDNNMs = nil }
        let result = readiness(days)

        #expect(result.hrvCoverage?.metric == .rmssd)
        #expect(result.hrvCoverage?.latestDay == today)
        #expect(result.hrvCoverage?.canCompare == false)
        #expect(result.hrvCoverage?.baselineReadings == 2)
    }

    // MARK: - Natural cycle (`hrv-cycle-phase`)

    @Test func lowHRVInANaturalCycleIsContextNotRed() {
        let days = history(recentHRV: [42, 44, 43, 45, 44, 46, 45], todayResting: 58)

        let result = ReadinessRules.readiness(
            today: today, history: days, checkIn: nil, tracksNaturalCycle: true, calendar: calendar
        )

        #expect(result.level == .amber)
        #expect(result.reasons.contains(.hrvMayReflectCycle))
        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 7)))
    }

    @Test func aNaturalCycleDoesNotHideOtherPhysiologicalSignals() {
        let days = history(recentHRV: [42, 44, 43, 45, 44, 46, 45], todayResting: 58, todaySleepHours: 5)

        let result = ReadinessRules.readiness(
            today: today, history: days, checkIn: nil, tracksNaturalCycle: true, calendar: calendar
        )

        // Resting HR + short sleep are two signals with one physiological: still red.
        #expect(result.level == .red)
    }
}
