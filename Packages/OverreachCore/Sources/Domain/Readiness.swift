import Foundation

public enum ReadinessLevel: String, Codable, Sendable {
    /// Normal plan, intensity allowed.
    case green
    /// Easy running (Z1–2) or light strength.
    case amber
    /// Rest or walk.
    case red
    /// Not enough data to decide.
    case unknown
}

/// Why the app reached a readiness level. The UI localizes these; `Reports` describes them in plain English.
public enum ReadinessReason: Hashable, Codable, Sendable {
    case markedSick
    case symptomsLimitTraining
    case hrvBelowBaseline(nights: Int)
    case restingHeartRateElevated(bpmAboveBaseline: Double)
    case shortSleep(hours: Double)
    /// Check-in energy, 1 (exhausted) … 5 (great).
    case lowEnergy(score: Int)
    /// Check-in muscle soreness, 0 (none) … 3 (very sore).
    case highSoreness(score: Int)
    case missingData
}

/// Coverage of the HRV series selected for readiness. Window lengths are calendar days.
public struct HRVCoverage: Hashable, Codable, Sendable {
    public let metric: HRVMetric?
    public let latestDay: CalendarDay
    public let recentDays: Int
    public let recentReadings: Int
    public let minimumRecentReadings: Int
    public let baselineDays: Int
    public let baselineReadings: Int
    public let minimumBaselineReadings: Int

    public var canCompare: Bool {
        recentReadings >= minimumRecentReadings && baselineReadings >= minimumBaselineReadings
    }

    public init(
        metric: HRVMetric?, latestDay: CalendarDay, recentDays: Int, recentReadings: Int, minimumRecentReadings: Int,
        baselineDays: Int, baselineReadings: Int, minimumBaselineReadings: Int
    ) {
        self.metric = metric
        self.latestDay = latestDay
        self.recentDays = recentDays
        self.recentReadings = recentReadings
        self.minimumRecentReadings = minimumRecentReadings
        self.baselineDays = baselineDays
        self.baselineReadings = baselineReadings
        self.minimumBaselineReadings = minimumBaselineReadings
    }
}

/// The daily traffic light, always with its reasons.
public struct Readiness: Hashable, Codable, Sendable {
    public var level: ReadinessLevel
    public var reasons: [ReadinessReason]
    public var hrvCoverage: HRVCoverage?

    public init(level: ReadinessLevel, reasons: [ReadinessReason] = [], hrvCoverage: HRVCoverage? = nil) {
        self.level = level
        self.reasons = reasons
        self.hrvCoverage = hrvCoverage
    }
}
