import Domain
import Foundation
import Testing

@Suite("Health aggregation")
struct HealthAggregationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!  // swiftlint:disable:this force_unwrapping
    }

    private var range: ClosedRange<CalendarDay> {
        CalendarDay(year: 2026, month: 11, day: 18)...CalendarDay(year: 2026, month: 11, day: 19)
    }

    @Test func sleepBelongsToTheDayItEndsWithStagesAndNoDoubleCounting() throws {
        let samples = HealthSamples(sleep: [
            SleepSample(start: date(18, 23), end: date(19, 7), stage: .inBed),  // the phone: in bed only
            SleepSample(start: date(18, 23, 30), end: date(19, 1), stage: .light),  // the watch: stages
            SleepSample(start: date(19, 1), end: date(19, 2, 30), stage: .deep),
            SleepSample(start: date(19, 2, 30), end: date(19, 2, 45), stage: .awake),
            SleepSample(start: date(19, 2, 45), end: date(19, 4), stage: .rem),
            SleepSample(start: date(19, 4), end: date(19, 6, 30), stage: .light),
            SleepSample(start: date(19, 4), end: date(19, 6, 30), stage: .asleep),  // a second source, same night
        ])
        let days = HealthAggregation.dailyMetrics(from: samples, in: range, source: .appleHealth, calendar: calendar)

        let night = try #require(days.first { $0.day == CalendarDay(year: 2026, month: 11, day: 19) })
        #expect(night.sleepSeconds == 6.75 * 3_600)  // 23:30–02:30 and 02:45–06:30, awake excluded
        #expect(night.deepSleepSeconds == 1.5 * 3_600)
        #expect(night.remSleepSeconds == 1.25 * 3_600)
        #expect(abs((night.awakeSeconds ?? 0) - 15 * 60) < 0.001)
        #expect(night.sources == [.appleHealth])
        #expect(!days.contains { $0.day == CalendarDay(year: 2026, month: 11, day: 18) })
    }

    @Test func hrvUsesTheNightRestingHeartRateTheLatestValue() throws {
        let samples = HealthSamples(
            sleep: [SleepSample(start: date(18, 23), end: date(19, 7), stage: .asleep)],
            restingHeartRate: [TimedValue(date: date(19, 8), value: 55), TimedValue(date: date(19, 20), value: 52)],
            hrv: [
                TimedValue(date: date(19, 2), value: 40), TimedValue(date: date(19, 5), value: 50),
                TimedValue(date: date(19, 15), value: 20),  // daytime, ignored when there are night samples
            ],
            oxygenSaturation: [TimedValue(date: date(19, 3), value: 96), TimedValue(date: date(19, 4), value: 98)],
            steps: [CalendarDay(year: 2026, month: 11, day: 19): 8_412]
        )
        let day = try #require(
            HealthAggregation.dailyMetrics(from: samples, in: range, source: .appleHealth, calendar: calendar).last
        )
        #expect(day.hrvNightlyAverageMs == 45)
        #expect(day.hrvMetric == .sdnn)
        #expect(day.restingHeartRate == 52)
        #expect(day.spo2Average == 97)
        #expect(day.steps == 8_412)
    }

    @Test func withoutSleepHRVIsTheDayMean() throws {
        let samples = HealthSamples(hrv: [TimedValue(date: date(18, 10), value: 30), TimedValue(date: date(18, 18), value: 50)])
        let day = try #require(
            HealthAggregation.dailyMetrics(from: samples, in: range, source: .appleHealth, calendar: calendar).first
        )
        #expect(day.hrvNightlyAverageMs == 40)
        #expect(day.sleepSeconds == nil)
    }

    @Test func noSamplesMeansNoDays() {
        #expect(HealthAggregation.dailyMetrics(from: HealthSamples(), in: range, source: .appleHealth).isEmpty)
    }
}
