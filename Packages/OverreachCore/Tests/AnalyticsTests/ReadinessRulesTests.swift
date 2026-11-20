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
        #expect(readiness(history()) == Readiness(level: .green))
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
    }

    @Test func oneLowNightInsideANormalWeekStaysGreen() {
        #expect(readiness(history(recentHRV: [45, 57, 58, 56, 57, 55, 58])).level == .green)
    }

    @Test func HRVNeedsThreeRecentNights() {
        var days = history(recentHRV: [40, 41])
        for index in days.indices where (2..<7).contains(index) { days[index].hrvNightlyAverageMs = nil }

        #expect(readiness(days).level == .green)
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

        #expect(result == Readiness(level: .amber, reasons: [.shortSleep(hours: 5)]))
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

    // MARK: - One HRV measure per baseline

    @Test func valuesOfAnotherMeasureNeverJoinTheBaseline() {
        // Garmin RMSSD around 55 ms on most nights; the Apple Watch filled the last week with SDNN around 35 ms.
        // Mixed, the week would look far below the baseline; kept apart, there is too little SDNN to judge and
        // the Garmin nights of the week are missing, so HRV is skipped rather than misread.
        let days = history().map { day -> DailyMetrics in
            var day = day
            let isRecent = day.day > today.adding(days: -7, calendar: calendar)
            day.hrvNightlyAverageMs = isRecent ? 35 : day.hrvNightlyAverageMs
            day.hrvMeasure = isRecent ? .sleepSDNN : .overnightRMSSD
            return day
        }

        let result = readiness(days)

        #expect(result.level == .green)
        #expect(!result.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } })
    }

    @Test func theMeasureWithMoreNightsIsTheOneUsed() {
        // SDNN every night with a low week; a few stray Garmin nights at a different scale are ignored.
        let days = history(recentHRV: [44, 46, 43, 47, 45, 52, 48]).enumerated().map { index, day -> DailyMetrics in
            var day = day
            day.hrvMeasure = .sleepSDNN
            if index > 20, index.isMultiple(of: 9) {
                day.hrvNightlyAverageMs = 120
                day.hrvMeasure = .overnightRMSSD
            }
            return day
        }

        #expect(readiness(days).reasons == [.hrvBelowBaseline(nights: 7)])
    }

    @Test func oldGarminDataIsRecognisedByItsBaselineFields() {
        var day = DailyMetrics(day: today)
        day.hrvNightlyAverageMs = 60
        day.hrvStatus = "BALANCED"
        #expect(day.resolvedHRVMeasure == .overnightRMSSD)

        day.hrvStatus = nil
        #expect(day.resolvedHRVMeasure == nil)
        day.hrvMeasure = .daytimeSDNN
        #expect(day.resolvedHRVMeasure == .daytimeSDNN)
    }

    @Test func mergingKeepsTheMeasureWithItsValue() {
        var garmin = DailyMetrics(day: today, sources: [.garmin])
        garmin.restingHeartRate = 48
        var health = DailyMetrics(day: today, sources: [.appleHealth])
        health.hrvNightlyAverageMs = 40
        health.hrvMeasure = .sleepSDNN

        let merged = garmin.merging(health)

        #expect(merged.hrvNightlyAverageMs == 40)
        #expect(merged.hrvMeasure == .sleepSDNN)
    }

    // MARK: - Natural cycle

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
