import Analytics
import Domain
import Foundation
import Testing

@Suite("Carry-over of a recorded run")
struct RunCarryoverTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let lift = Date(timeIntervalSince1970: 1_800_000_000 + 40 * 3_600)

    /// An easy 40-minute, 7 km run with a training effect below every threshold.
    private func easy(
        id: String = "run", minutes: Double = 40, kilometers: Double = 7, gain: Double? = 20, aerobic: Double? = 2.5,
        anaerobic: Double? = 0.3, heartRate: Double? = 140
    ) -> RunActivity {
        RunActivity(id: id, source: .garmin, startedAt: start, durationSeconds: minutes * 60,
                    distanceMeters: kilometers * 1_000, averageHeartRate: heartRate, elevationGainMeters: gain,
                    aerobicTrainingEffect: aerobic, anaerobicTrainingEffect: anaerobic)
    }

    private func recent(daysBefore days: Double = 3, kilometers: Double = 7, id: String = "earlier") -> RunActivity {
        RunActivity(id: id, source: .garmin, startedAt: start.addingTimeInterval(-days * 86_400),
                    durationSeconds: 40 * 60, distanceMeters: kilometers * 1_000)
    }

    private func assessment(
        _ run: RunActivity, recent runs: [RunActivity]? = nil, checkIn: CheckIn? = nil, next: Date? = nil,
        pain: RunPainReport? = nil, tag: PlannedRun.Purpose? = nil, settings: RunCarryover.Settings = .init()
    ) -> RunCarryover.Assessment {
        RunCarryover.assessment(run: run, recentRuns: runs ?? [recent()], checkIn: checkIn,
                                nextSessionStart: next ?? lift, painReport: pain, tag: tag, settings: settings)
    }

    @Test func anEasyUsualRunWithTimeBeforeTheLiftIsLight() {
        let result = assessment(easy())
        #expect(result.level == .light)
        #expect(result.reasons.isEmpty)
        #expect(!result.intensityUnknown)
    }

    @Test func trainingEffectOrTagMakesItHard() {
        #expect(assessment(easy(anaerobic: 2.0)).reasons == [.hard])
        #expect(assessment(easy(aerobic: 4.0)).reasons == [.hard])
        #expect(assessment(easy(aerobic: 3.9, anaerobic: 1.9)).level == .light)
        #expect(assessment(easy(), tag: .intervals).reasons == [.hard])
        #expect(assessment(easy(), tag: .race).reasons == [.hard])
        #expect(assessment(easy(), tag: .easy).level == .light)
    }

    @Test func overSixtyMinutesOrOverTheLongestRecentRunIsLong() {
        #expect(assessment(easy(minutes: 61, kilometers: 7)).reasons == [.long])
        #expect(assessment(easy(minutes: 60, kilometers: 7)).level == .light)
        #expect(assessment(easy(kilometers: 7.8), recent: [recent(kilometers: 7)]).reasons == [.long])
        #expect(assessment(easy(kilometers: 7.7), recent: [recent(kilometers: 7)]).level == .light)
        // Older than 30 days does not count.
        let history = [recent(kilometers: 7), recent(daysBefore: 40, kilometers: 20, id: "old")]
        #expect(assessment(easy(kilometers: 12), recent: history).reasons == [.long])
    }

    @Test func steepClimbsAreHilly() {
        #expect(assessment(easy(kilometers: 7, gain: 105)).reasons == [.hilly])
        #expect(assessment(easy(kilometers: 7, gain: 104)).level == .light)
        #expect(assessment(easy(gain: nil)).level == .light)
    }

    @Test func noRunInTheLastFourteenDaysIsUnaccustomed() {
        #expect(assessment(easy(), recent: []).reasons == [.unaccustomed])
        #expect(assessment(easy(), recent: [recent(daysBefore: 15)]).reasons == [.unaccustomed])
        #expect(assessment(easy(), recent: [recent(daysBefore: 13)]).level == .light)
    }

    @Test func theRunItselfAndItsCopyAreNotPriorRuns() {
        let run = easy()
        let copy = RunActivity(id: "other-source", source: .appleHealth, startedAt: start.addingTimeInterval(30),
                               durationSeconds: 40 * 60, distanceMeters: 7_000)
        #expect(assessment(run, recent: [run, copy]).reasons == [.unaccustomed])
    }

    @Test func lessThanTwentyFourHoursBeforeTheLiftIsClose() {
        let end = start.addingTimeInterval(40 * 60)
        #expect(assessment(easy(), next: end.addingTimeInterval(23.9 * 3_600)).reasons == [.close])
        #expect(assessment(easy(), next: end.addingTimeInterval(24 * 3_600)).level == .light)
    }

    @Test func sorenessAndPainThatHoldsAreNotable() {
        let day = CalendarDay(year: 2026, month: 11, day: 20)
        #expect(assessment(easy(), checkIn: CheckIn(day: day, soreness: 3)).reasons == [.soreness])
        #expect(assessment(easy(), checkIn: CheckIn(day: day, soreness: 2)).level == .light)

        var held = RunPainReport(easy())
        held.answer(during: 2, after: 5, settledByMorning: true)
        #expect(assessment(easy(), pain: held).reasons == [.pain])
        var tolerated = RunPainReport(easy())
        tolerated.answer(during: 1, after: 3, settledByMorning: true)
        #expect(assessment(easy(), pain: tolerated).level == .light)
        var unsettled = RunPainReport(easy())
        unsettled.answer(during: 1, after: 2, settledByMorning: false)
        #expect(assessment(easy(), pain: unsettled).reasons == [.pain])
    }

    @Test func aMissingDurationIsUnknown() {
        #expect(assessment(easy(minutes: 0)).level == .unknown)
        #expect(RunCarryover.assess(run: easy(minutes: 0), recentRuns: [], checkIn: nil, nextSessionStart: lift)
            == .unknown)
    }

    @Test func appleHealthRunsWithoutIntensityUseTheOtherCriteriaAndSayIntensityIsUnknown() {
        let apple = easy(aerobic: nil, anaerobic: nil, heartRate: nil)
        let light = assessment(apple)
        #expect(light.level == .light)
        #expect(light.intensityUnknown)
        let long = assessment(easy(minutes: 75, aerobic: nil, anaerobic: nil, heartRate: nil))
        #expect(long.reasons == [.long])
        #expect(long.intensityUnknown)
        // A tag or heart rate alone counts as intensity.
        #expect(!assessment(apple, tag: .easy).intensityUnknown)
    }

    @Test func thresholdsComeFromSettings() {
        var settings = RunCarryover.Settings()
        settings.longMinutes = 30
        settings.closeHours = 48
        #expect(Set(assessment(easy(), settings: settings).reasons) == [.long, .close])
    }
}
