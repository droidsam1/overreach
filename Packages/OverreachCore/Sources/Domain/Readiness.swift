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
    case hrvBelowBaseline(nights: Int)
    case restingHeartRateElevated(bpmAboveBaseline: Double)
    case shortSleep(hours: Double)
    case missingData
}

/// The daily traffic light, always with its reasons.
public struct Readiness: Hashable, Codable, Sendable {
    public var level: ReadinessLevel
    public var reasons: [ReadinessReason]

    public init(level: ReadinessLevel, reasons: [ReadinessReason] = []) {
        self.level = level
        self.reasons = reasons
    }
}
