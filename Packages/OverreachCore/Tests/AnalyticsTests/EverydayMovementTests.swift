import Analytics
import Domain
import Foundation
import Testing

@Suite("Everyday movement against the usual day")
struct EverydayMovementTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 21)

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    private func walk(
        _ offset: Int, minutes: Double, hour: Int = 8, source: DataSourceKind = .appleHealth
    ) -> WalkBout {
        let start = day(offset).startDate(in: calendar).addingTimeInterval(Double(hour) * 3_600)
        return WalkBout(start: start, durationSeconds: minutes * 60, source: source)
    }

    /// Four weeks of commuting: about 9,000 steps and two 20-minute dog walks a day.
    private func commuteMonth() -> [DailyActivity] {
        (-28 ... -1).map { offset in
            DailyActivity(day: day(offset), steps: 9_000 + (offset % 2) * 1_000,
                          walks: [walk(offset, minutes: 20), walk(offset, minutes: 20, hour: 19)])
        }
    }

    @Test func theUsualDayIsTheMedianOfTheLastFourWeeks() {
        let baseline = EverydayMovement.baseline(commuteMonth(), before: today, calendar: calendar)
        #expect(baseline.steps == 8_500)
        #expect(baseline.walkingMinutes == 40)
    }

    @Test func withTooFewDaysThereIsNoBaselineAndNoSignal() {
        let week = (-7 ... -1).map { DailyActivity(day: day($0), steps: 1_000) }
        #expect(EverydayMovement.baseline(week, before: today, calendar: calendar) == EverydayMovement.Baseline())
        #expect(EverydayMovement.signals(week, today: today, calendar: calendar).isEmpty)
        #expect(EverydayMovement.signals([], today: today, calendar: calendar).isEmpty)
    }

    @Test func withoutAnyRecordedWalkThereIsNoWalkingBaseline() {
        let steps = (-28 ... -1).map { DailyActivity(day: day($0), steps: 9_000) }
        let baseline = EverydayMovement.baseline(steps, before: today, calendar: calendar)
        #expect(baseline.steps == 9_000)
        #expect(baseline.walkingMinutes == nil)
        #expect(EverydayMovement.extraWalkingMinutes(DailyActivity(day: today, walks: [walk(0, minutes: 120)]),
                                                     baseline: baseline) == 0)
    }

    @Test func routineWalkingAddsNoExtraLoad() {
        let baseline = EverydayMovement.baseline(commuteMonth(), before: today, calendar: calendar)
        let usual = DailyActivity(day: today, steps: 9_000,
                                  walks: [walk(0, minutes: 25), walk(0, minutes: 15, hour: 19)])
        #expect(EverydayMovement.extraWalkingMinutes(usual, baseline: baseline) == 0)
    }

    @Test func aSaturdayHikeIsASpikeTheNextDay() {
        var activity = commuteMonth()
        activity[activity.count - 1] = DailyActivity(day: day(-1), steps: 24_000,
                                                     walks: [walk(-1, minutes: 20), walk(-1, minutes: 150, hour: 10)])
        let signals = EverydayMovement.signals(activity, today: today, calendar: calendar)
        #expect(signals == [.walkingSpike(day: day(-1), minutes: 170, baselineMinutes: 40)])
        #expect(signals.first?.evidence == MovementEvidence.walkingAboveBaseline)
    }

    @Test func aLongerDogWalkIsNotASpike() {
        var activity = commuteMonth()
        activity[activity.count - 1] = DailyActivity(day: day(-1), steps: 11_000,
                                                     walks: [walk(-1, minutes: 50), walk(-1, minutes: 30, hour: 19)])
        #expect(EverydayMovement.signals(activity, today: today, calendar: calendar).isEmpty)
    }

    @Test func threeVeryLowDaysAreASignalButTodaysPartialCountIsIgnored() {
        var activity = commuteMonth().map { DailyActivity(day: $0.day, steps: $0.steps) }
        for offset in -3 ... -1 { activity[activity.count + offset] = DailyActivity(day: day(offset), steps: 2_400) }
        activity.append(DailyActivity(day: today, steps: 300))
        let signals = EverydayMovement.signals(activity, today: today, calendar: calendar)
        #expect(signals == [.stepsFarBelowBaseline(days: 3, averageSteps: 2_400, baselineSteps: 8_000)])
        #expect(signals.first?.evidence.level == .moderate)
    }

    @Test func lowStepsNeedEveryRecentDayMeasuredAndLow() {
        var activity = commuteMonth().map { DailyActivity(day: $0.day, steps: $0.steps) }
        activity[activity.count - 1] = DailyActivity(day: day(-1), steps: 2_000)
        activity[activity.count - 2] = DailyActivity(day: day(-2), steps: 6_000)  // above 5,000: not far below
        activity.remove(at: activity.count - 3)  // no data three days ago
        #expect(EverydayMovement.signals(activity, today: today, calendar: calendar).isEmpty)
    }

    @Test func theSameWalkFromTwoSourcesCountsOnceWithGarminFirst() {
        let garmin = walk(0, minutes: 60, source: .garmin)
        let health = WalkBout(start: garmin.start.addingTimeInterval(120), durationSeconds: 3_500, source: .appleHealth)
        let evening = walk(0, minutes: 30, hour: 19)
        let walks = EverydayMovement.removingDuplicateWalks([health, evening, garmin])
        #expect(walks == [garmin, evening])
    }
}
