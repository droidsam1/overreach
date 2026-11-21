import Foundation

/// Which heart rate variability statistic a source reports. They are not interchangeable (ADR-0024): Garmin reports
/// nightly RMSSD, Apple Watch reports SDNN from short readings. A baseline only ever compares nights of one kind
/// (ADR-0025).
public enum HRVMetric: String, Codable, Sendable, CaseIterable {
    case rmssd, sdnn

    /// Where readings of this statistic come from today: Garmin's Personal API reports nightly RMSSD, Apple Health
    /// stores SDNN. A second source of the same statistic would need its own series (ADR-0025).
    public var source: DataSourceKind {
        switch self {
        case .rmssd: .garmin
        case .sdnn: .appleHealth
        }
    }
}

/// When the readings behind a night's HRV value were taken. Readings from sleep and from the day are different
/// protocols and are never compared with each other (ADR-0032).
public enum HRVReadingWindow: String, Codable, Sendable, CaseIterable {
    case sleep, daytime
}

/// Everything known about one day of recovery. Every field is optional: what is available depends on the
/// watch model and on which sources the user connected.
public struct DailyMetrics: Hashable, Codable, Sendable {
    public var day: CalendarDay

    // MARK: Recovery
    /// Nightly RMSSD (Garmin's whole-night average), in ms.
    public var hrvRMSSDMs: Double?
    /// Nightly SDNN (mean of Apple Watch readings during sleep), in ms.
    public var hrvSDNNMs: Double?
    /// When the SDNN readings were taken: `.daytime` when the day had no sleep readings. `nil` in data written
    /// before ADR-0032, read as `.sleep`. Garmin's RMSSD is always whole-night.
    public var hrvSDNNWindow: HRVReadingWindow?
    /// Garmin's highest 5-minute RMSSD of the night. Context only.
    public var hrvNightlyHighMs: Double?
    public var hrvBaselineLowMs: Double?
    public var hrvBaselineHighMs: Double?
    /// Source label, e.g. Garmin "BALANCED", "UNBALANCED", "LOW".
    public var hrvStatus: String?
    public var restingHeartRate: Double?
    /// Which source supplied `restingHeartRate` after a merge. `nil` when the day has a single source.
    public var restingHeartRateSource: DataSourceKind?
    public var bodyBatteryHigh: Double?
    public var bodyBatteryLow: Double?
    public var averageStress: Double?
    public var respirationRate: Double?
    public var spo2Average: Double?

    // MARK: Sleep
    public var sleepSeconds: Double?
    /// Which source supplied `sleepSeconds` after a merge. `nil` when the day has a single source.
    public var sleepSource: DataSourceKind?
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

    /// The night's value of one HRV statistic. RMSSD and SDNN are separate series and never stand in for each
    /// other (ADR-0025).
    public func hrv(_ metric: HRVMetric) -> Double? {
        switch metric {
        case .rmssd: hrvRMSSDMs
        case .sdnn: hrvSDNNMs
        }
    }

    public mutating func setHRV(_ value: Double?, _ metric: HRVMetric) {
        switch metric {
        case .rmssd: hrvRMSSDMs = value
        case .sdnn: hrvSDNNMs = value
        }
    }

    /// When the readings behind the night's value of `metric` were taken, or `nil` without a value.
    public func hrvWindow(_ metric: HRVMetric) -> HRVReadingWindow? {
        guard hrv(metric) != nil else { return nil }
        return switch metric {
        case .rmssd: .sleep
        case .sdnn: hrvSDNNWindow ?? .sleep
        }
    }

    /// The source of `restingHeartRate`, or `nil` without a value.
    public var restingHeartRateOrigin: DataSourceKind? {
        restingHeartRate == nil ? nil : restingHeartRateSource ?? singleSource
    }

    /// The source of `sleepSeconds`, or `nil` without a value.
    public var sleepOrigin: DataSourceKind? {
        sleepSeconds == nil ? nil : sleepSource ?? singleSource
    }

    private var singleSource: DataSourceKind? {
        sources.count == 1 ? sources.first : nil
    }

    /// The statistic shown for this night when one value is displayed: RMSSD when both exist.
    public var hrvMetric: HRVMetric? {
        HRVMetric.allCases.first { hrv($0) != nil }
    }

    /// The night's HRV for display, reports and AI context, always next to `hrvMetric`. Rules use `hrv(_:)`.
    public var hrvNightlyAverageMs: Double? {
        hrvMetric.flatMap(hrv)
    }

    /// Returns a copy where every missing value is filled from `other`. Values already present win, so merge
    /// sources in priority order: `garmin.merging(health)` keeps Garmin's values when both have them.
    public func merging(_ other: DailyMetrics) -> DailyMetrics {
        var merged = self
        // Each statistic is its own series, so a night can keep Garmin's RMSSD and Apple's SDNN.
        merged.hrvRMSSDMs = hrvRMSSDMs ?? other.hrvRMSSDMs
        merged.hrvSDNNMs = hrvSDNNMs ?? other.hrvSDNNMs
        merged.hrvSDNNWindow = hrvSDNNMs != nil ? hrvSDNNWindow : other.hrvSDNNWindow
        merged.hrvNightlyHighMs = hrvNightlyHighMs ?? other.hrvNightlyHighMs
        merged.hrvBaselineLowMs = hrvBaselineLowMs ?? other.hrvBaselineLowMs
        merged.hrvBaselineHighMs = hrvBaselineHighMs ?? other.hrvBaselineHighMs
        merged.hrvStatus = hrvStatus ?? other.hrvStatus
        merged.restingHeartRate = restingHeartRate ?? other.restingHeartRate
        merged.restingHeartRateSource = restingHeartRateOrigin ?? other.restingHeartRateOrigin
        merged.bodyBatteryHigh = bodyBatteryHigh ?? other.bodyBatteryHigh
        merged.bodyBatteryLow = bodyBatteryLow ?? other.bodyBatteryLow
        merged.averageStress = averageStress ?? other.averageStress
        merged.respirationRate = respirationRate ?? other.respirationRate
        merged.spo2Average = spo2Average ?? other.spo2Average
        merged.sleepSeconds = sleepSeconds ?? other.sleepSeconds
        merged.sleepSource = sleepOrigin ?? other.sleepOrigin
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
