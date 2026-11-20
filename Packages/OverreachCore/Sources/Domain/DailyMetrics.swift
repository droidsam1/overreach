import Foundation

/// Which heart rate variability statistic a source reports. They are not interchangeable (ADR-0024): Garmin reports
/// nightly RMSSD, Apple Watch reports SDNN from short readings. A baseline only ever compares nights of one kind.
public enum HRVMetric: String, Codable, Sendable, CaseIterable {
    case rmssd, sdnn
}

/// Everything known about one day of recovery. Every field is optional: what is available depends on the
/// watch model and on which sources the user connected.
public struct DailyMetrics: Hashable, Codable, Sendable {
    public var day: CalendarDay

    // MARK: Recovery
    public var hrvNightlyAverageMs: Double?
    /// The statistic behind the HRV values of this day. `nil` for data stored before it was recorded.
    public var hrvMetric: HRVMetric?
    public var hrvNightlyHighMs: Double?
    public var hrvBaselineLowMs: Double?
    public var hrvBaselineHighMs: Double?
    /// Source label, e.g. Garmin "BALANCED", "UNBALANCED", "LOW".
    public var hrvStatus: String?
    public var restingHeartRate: Double?
    public var bodyBatteryHigh: Double?
    public var bodyBatteryLow: Double?
    public var averageStress: Double?
    public var respirationRate: Double?
    public var spo2Average: Double?

    // MARK: Sleep
    public var sleepSeconds: Double?
    public var deepSleepSeconds: Double?
    public var remSleepSeconds: Double?
    public var lightSleepSeconds: Double?
    public var awakeSeconds: Double?
    public var sleepScore: Double?

    // MARK: Training
    /// Source label, e.g. Garmin "PRODUCTIVE", "OVERREACHING".
    public var trainingStatus: String?
    public var trainingReadiness: Double?
    public var acuteLoad: Double?
    public var recoveryTimeHours: Double?
    public var vo2Max: Double?
    public var steps: Int?

    /// Sources that contributed at least one value.
    public var sources: Set<DataSourceKind>

    public init(day: CalendarDay, sources: Set<DataSourceKind> = []) {
        self.day = day
        self.sources = sources
    }

    /// Returns a copy where every missing value is filled from `other`. Values already present win, so merge
    /// sources in priority order: `garmin.merging(health)` keeps Garmin's values when both have them.
    public func merging(_ other: DailyMetrics) -> DailyMetrics {
        var merged = self
        merged.hrvNightlyAverageMs = hrvNightlyAverageMs ?? other.hrvNightlyAverageMs
        // The statistic travels with the value it describes, never mixed across sources.
        merged.hrvMetric = hrvNightlyAverageMs != nil ? hrvMetric : other.hrvMetric
        merged.hrvNightlyHighMs = hrvNightlyHighMs ?? other.hrvNightlyHighMs
        merged.hrvBaselineLowMs = hrvBaselineLowMs ?? other.hrvBaselineLowMs
        merged.hrvBaselineHighMs = hrvBaselineHighMs ?? other.hrvBaselineHighMs
        merged.hrvStatus = hrvStatus ?? other.hrvStatus
        merged.restingHeartRate = restingHeartRate ?? other.restingHeartRate
        merged.bodyBatteryHigh = bodyBatteryHigh ?? other.bodyBatteryHigh
        merged.bodyBatteryLow = bodyBatteryLow ?? other.bodyBatteryLow
        merged.averageStress = averageStress ?? other.averageStress
        merged.respirationRate = respirationRate ?? other.respirationRate
        merged.spo2Average = spo2Average ?? other.spo2Average
        merged.sleepSeconds = sleepSeconds ?? other.sleepSeconds
        merged.deepSleepSeconds = deepSleepSeconds ?? other.deepSleepSeconds
        merged.remSleepSeconds = remSleepSeconds ?? other.remSleepSeconds
        merged.lightSleepSeconds = lightSleepSeconds ?? other.lightSleepSeconds
        merged.awakeSeconds = awakeSeconds ?? other.awakeSeconds
        merged.sleepScore = sleepScore ?? other.sleepScore
        merged.trainingStatus = trainingStatus ?? other.trainingStatus
        merged.trainingReadiness = trainingReadiness ?? other.trainingReadiness
        merged.acuteLoad = acuteLoad ?? other.acuteLoad
        merged.recoveryTimeHours = recoveryTimeHours ?? other.recoveryTimeHours
        merged.vo2Max = vo2Max ?? other.vo2Max
        merged.steps = steps ?? other.steps
        merged.sources = sources.union(other.sources)
        return merged
    }
}
