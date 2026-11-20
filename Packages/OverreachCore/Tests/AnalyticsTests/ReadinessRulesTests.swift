import Analytics
import Domain
import Foundation
import Testing

@Suite("Readiness rules")
struct ReadinessRulesTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(year: 2026, month: 11, day: 19) }

    /// A realistic history: nightly HRV around 55 ms (± ~5), resting HR around 50 bpm, 7.5 h of sleep.
    private func history(
        days: Int = 60, recentHRV: [Double]? = nil, todayResting: Double? = nil, todaySleepHours: Double? = 7.5
    ) -> [DailyMetrics] {
        let wobble: [Double] = [0, 4, -3, 6, -5, 2, -1, 5, -4, 3]
        return (0...days).map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.appleHealth])
            metrics.hrvNightlyAverageMs = 55 + wobble[offset % wobble.count]
            metrics.restingHeartRate = 50 + wobble[offset % wobble.count] / 5
            metrics.sleepSeconds = 7.5 * 3_600
            if let recentHRV, offset < recentHRV.count { metrics.hrvNightlyAverageMs = recentHRV[offset] }
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
        #expect(readiness([]) == Readiness(level: .unknown, reasons: [.missingData]))
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
        for index in days.indices where (2..<7).contains(index) { days[index].hrvNightlyAverageMs = nil }

        let result = readiness(days)
        #expect(result.level == .green)
        #expect(result.hrvCoverage?.recentReadings == 2)
        #expect(result.hrvCoverage?.canCompare == false)
    }

    @Test func invalidAndDifferentStatisticReadingsDoNotCountTowardCoverage() {
        var days = switchedToGarmin(garminNights: 30)
        days[0].hrvNightlyAverageMs = .infinity
        days[1].hrvNightlyAverageMs = 24
        days[2].hrvNightlyAverageMs = 24
        days[3].hrvNightlyAverageMs = nil
        days[4].hrvNightlyAverageMs = 0
        days[5].hrvNightlyAverageMs = 24
        days[6].hrvMetric = .sdnn

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

        #expect(result == Readiness(level: .red, reasons: [.markedSick]))
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
        ]
        let keys = reasons.map { ReadinessRules.evidence(for: $0).key }

        #expect(keys == [
            "illness-return", "readiness-hrv", "hrv-cycle-phase", "readiness-resting-hr", "readiness-sleep", "readiness-subjective",
            "readiness-subjective", "readiness-combination",
        ])
    }

    // MARK: HRV statistics (ADR-0024)

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
                day.hrvNightlyAverageMs = 35 + Double(offset % 3)
                day.hrvMetric = .rmssd
                day.sources = [.garmin]
            } else {
                day.hrvMetric = .sdnn
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
        for index in days.indices where days[index].hrvMetric == .rmssd {
            let offset = calendar.dateComponents(
                [.day], from: days[index].day.startDate(in: calendar), to: today.startDate(in: calendar)
            ).day ?? 0
            if offset < 7 { days[index].hrvNightlyAverageMs = 26 }  // a real drop in RMSSD
        }

        let result = readiness(days)

        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 7)))
    }

    @Test func mergingKeepsEachValueWithItsStatistic() {
        var garmin = DailyMetrics(day: today, sources: [.garmin])
        garmin.sleepScore = 80
        var health = DailyMetrics(day: today, sources: [.appleHealth])
        health.hrvNightlyAverageMs = 50
        health.hrvMetric = .sdnn

        let merged = garmin.merging(health)  // Garmin has no HRV tonight: the SDNN value comes with its label
        #expect(merged.hrvNightlyAverageMs == 50 && merged.hrvMetric == .sdnn)

        garmin.hrvNightlyAverageMs = 38
        garmin.hrvMetric = .rmssd
        let both = garmin.merging(health)
        #expect(both.hrvNightlyAverageMs == 38 && both.hrvMetric == .rmssd)
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
