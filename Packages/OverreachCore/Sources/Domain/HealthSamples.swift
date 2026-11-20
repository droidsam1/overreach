import Foundation

/// A sleep interval as Apple Health stores it (one source may write in bed, another the stages).
public struct SleepSample: Hashable, Sendable {
    public enum Stage: String, Hashable, Sendable {
        case inBed, asleep, light, deep, rem, awake

        var isAsleep: Bool { self == .asleep || self == .light || self == .deep || self == .rem }
    }

    public var start: Date
    public var end: Date
    public var stage: Stage

    public init(start: Date, end: Date, stage: Stage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

/// A measured value at a moment, in the unit the caller chose (e.g. HRV in ms, resting HR in bpm).
public struct TimedValue: Hashable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Raw health samples for a range of days, before they are turned into `DailyMetrics`.
public struct HealthSamples: Sendable {
    public var sleep: [SleepSample]
    public var restingHeartRate: [TimedValue]
    /// HRV in ms. Apple Watch writes SDNN; Garmin writes no HRV to Health (it comes from `GarminSource`).
    public var hrv: [TimedValue]
    public var vo2Max: [TimedValue]
    public var respirationRate: [TimedValue]
    /// Oxygen saturation in percent (0–100).
    public var oxygenSaturation: [TimedValue]
    /// Step totals per day.
    public var steps: [CalendarDay: Int]

    public init(
        sleep: [SleepSample] = [], restingHeartRate: [TimedValue] = [], hrv: [TimedValue] = [],
        vo2Max: [TimedValue] = [], respirationRate: [TimedValue] = [], oxygenSaturation: [TimedValue] = [],
        steps: [CalendarDay: Int] = [:]
    ) {
        self.sleep = sleep
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
        self.vo2Max = vo2Max
        self.respirationRate = respirationRate
        self.oxygenSaturation = oxygenSaturation
        self.steps = steps
    }
}

/// Turns health samples into one `DailyMetrics` per day. Pure, so the HealthKit adapter stays a thin reader.
public enum HealthAggregation {
    /// - Sleep belongs to the day it ends ("last night" is today's). Overlapping intervals from several sources
    ///   (a watch and the phone) are merged, so nothing is counted twice; "in bed" alone is not sleep.
    /// - HRV is the mean of the samples taken during that night's sleep, or of the day's samples without sleep;
    ///   `hrvMeasure` says which, so the two never share a baseline.
    /// - Resting heart rate is the day's latest value; VO2max, respiration and SpO2 are the day's mean.
    public static func dailyMetrics(
        from samples: HealthSamples, in range: ClosedRange<CalendarDay>, source: DataSourceKind,
        calendar: Calendar = .current
    ) -> [DailyMetrics] {
        let nights = sleepByDay(samples.sleep, calendar: calendar)
        var result: [DailyMetrics] = []
        var day = range.lowerBound
        while day <= range.upperBound {
            var metrics = DailyMetrics(day: day)
            let night = nights[day]
            if let night {
                metrics.sleepSeconds = night.asleep
                metrics.deepSleepSeconds = night.deep
                metrics.remSleepSeconds = night.rem
                metrics.lightSleepSeconds = night.light
                metrics.awakeSeconds = night.awake
            }
            let hrvToday = values(samples.hrv, on: day, calendar: calendar)
            let hrvAsleep = night.map { window in hrvToday.filter { window.window.contains($0.date) } } ?? []
            if let asleep = mean(hrvAsleep) {
                metrics.hrvNightlyAverageMs = asleep
                metrics.hrvMeasure = .sleepSDNN
            } else if let daytime = mean(hrvToday) {
                metrics.hrvNightlyAverageMs = daytime
                metrics.hrvMeasure = .daytimeSDNN
            }
            metrics.restingHeartRate = values(samples.restingHeartRate, on: day, calendar: calendar)
                .max { $0.date < $1.date }?.value
            metrics.vo2Max = mean(values(samples.vo2Max, on: day, calendar: calendar))
            metrics.respirationRate = mean(values(samples.respirationRate, on: day, calendar: calendar))
            metrics.spo2Average = mean(values(samples.oxygenSaturation, on: day, calendar: calendar))
            metrics.steps = samples.steps[day]
            if metrics != DailyMetrics(day: day) {
                metrics.sources = [source]
                result.append(metrics)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        return result
    }

    struct Night {
        var asleep = 0.0
        var deep: Double?
        var rem: Double?
        var light: Double?
        var awake: Double?
        var window: ClosedRange<Date>
    }

    /// Sleep totals per day the sleep ends.
    static func sleepByDay(_ samples: [SleepSample], calendar: Calendar) -> [CalendarDay: Night] {
        let asleep = merged(samples.filter { $0.stage.isAsleep })
        var nights: [CalendarDay: Night] = [:]
        for interval in asleep {
            let day = CalendarDay(interval.upperBound, calendar: calendar)
            var night = nights[day] ?? Night(window: interval)
            night.asleep += interval.upperBound.timeIntervalSince(interval.lowerBound)
            night.window = min(night.window.lowerBound, interval.lowerBound)...max(night.window.upperBound, interval.upperBound)
            nights[day] = night
        }
        for (day, night) in nights {
            var updated = night
            let inNight = samples.filter { night.window.contains($0.start) }
            updated.deep = total(merged(inNight.filter { $0.stage == .deep }))
            updated.rem = total(merged(inNight.filter { $0.stage == .rem }))
            updated.light = total(merged(inNight.filter { $0.stage == .light }))
            updated.awake = total(merged(inNight.filter { $0.stage == .awake }))
            nights[day] = updated
        }
        return nights
    }

    /// Union of the intervals, sorted.
    static func merged(_ samples: [SleepSample]) -> [ClosedRange<Date>] {
        let sorted = samples.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var result: [ClosedRange<Date>] = []
        for sample in sorted {
            if let last = result.last, sample.start <= last.upperBound {
                result[result.count - 1] = last.lowerBound...max(last.upperBound, sample.end)
            } else {
                result.append(sample.start...sample.end)
            }
        }
        return result
    }

    private static func total(_ intervals: [ClosedRange<Date>]) -> Double? {
        intervals.isEmpty ? nil : intervals.reduce(0) { $0 + $1.upperBound.timeIntervalSince($1.lowerBound) }
    }

    private static func values(_ values: [TimedValue], on day: CalendarDay, calendar: Calendar) -> [TimedValue] {
        values.filter { CalendarDay($0.date, calendar: calendar) == day }
    }

    private static func mean(_ values: [TimedValue]) -> Double? {
        values.isEmpty ? nil : values.reduce(0) { $0 + $1.value } / Double(values.count)
    }
}
