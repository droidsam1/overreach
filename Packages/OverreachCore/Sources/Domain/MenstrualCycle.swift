import Foundation

/// Menstrual cycle phase, used only as context (ADR-0009, `docs/design/cycle-aware-training.md`).
public enum CyclePhase: String, Codable, Sendable, CaseIterable {
    case menstrual, follicular, ovulatory, luteal, lateLuteal, unknown
}

public enum MenstrualFlow: String, Codable, Sendable, CaseIterable {
    case unspecified, light, medium, heavy
}

/// One day with menstrual bleeding, read from Apple Health or entered in the check-in.
public struct MenstrualEvent: Hashable, Codable, Sendable {
    public var day: CalendarDay
    public var flow: MenstrualFlow?
    /// Explicit start of a cycle (Health's `HKMetadataKeyMenstrualCycleStart`, or "period started today").
    public var isCycleStart: Bool
    public var source: DataSourceKind

    public init(day: CalendarDay, flow: MenstrualFlow? = nil, isCycleStart: Bool = false, source: DataSourceKind = .manual) {
        self.day = day
        self.flow = flow
        self.isCycleStart = isCycleStart
        self.source = source
    }
}

/// Cycle-related symptoms logged in the check-in, each 0 (none) … 3 (severe). Any user can log them.
public struct CycleSymptoms: Hashable, Codable, Sendable {
    public var cramps: Int?
    public var fatigue: Int?
    public var headache: Int?
    public var bloating: Int?

    public init(cramps: Int? = nil, fatigue: Int? = nil, headache: Int? = nil, bloating: Int? = nil) {
        self.cramps = cramps
        self.fatigue = fatigue
        self.headache = headache
        self.bloating = bloating
    }

    /// The most severe symptom, or `nil` if none was logged.
    public var maxSeverity: Int? {
        [cramps, fatigue, headache, bloating].compactMap { $0 }.max()
    }
}

/// Result of the phase estimator: always with a confidence and the reasons, never a medical claim.
public struct CyclePhaseEstimate: Hashable, Codable, Sendable {
    public var day: CalendarDay
    public var phase: CyclePhase
    /// 1-based day of the current cycle, if known.
    public var cycleDay: Int?
    /// 0 … 1.
    public var confidence: Double
    public var reasons: [String]

    public init(day: CalendarDay, phase: CyclePhase, cycleDay: Int? = nil, confidence: Double, reasons: [String] = []) {
        self.day = day
        self.phase = phase
        self.cycleDay = cycleDay
        self.confidence = confidence
        self.reasons = reasons
    }
}
