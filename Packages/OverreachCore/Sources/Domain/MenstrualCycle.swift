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

/// The two baseline windows of a natural cycle (`cycle-phase-baselines`): follicular = menstrual + follicular days,
/// luteal = luteal + late luteal days. Coarse on purpose: robust to the ± days of error of calendar estimation.
public enum CycleBaselineWindow: String, Hashable, Codable, Sendable, CaseIterable {
    case follicular, luteal
}

/// Result of the phase estimator (`cycle-phase-estimation`): coarse windows counted from period starts, always with a
/// confidence and the reasons, never a medical claim. Not persisted: recomputed from menstrual events.
public struct CyclePhaseEstimate: Hashable, Codable, Sendable {
    public enum Confidence: String, Hashable, Codable, Sendable {
        /// Regular known cycles: rules may use the phase.
        case high
        /// Context at most; no rule uses it.
        case low
    }

    /// Why the confidence is low.
    public enum Reason: String, Hashable, Codable, Sendable {
        /// Fewer than 2 complete cycles are known; the expected length is the 28-day default.
        case fewCycles
        /// A recent cycle was outside 21–35 days, or their lengths spread more than 7 days.
        case irregularCycles
        /// More than 3 days past the expected start: the phase is not assumed.
        case overdue
    }

    /// `.menstrual`, `.follicular`, `.luteal`, `.lateLuteal`, or `.unknown` when overdue. Never `.ovulatory`.
    public var phase: CyclePhase
    /// 1 = first day of the current period.
    public var cycleDay: Int
    /// Days, median of recent complete cycles (28 until 2 are known).
    public var expectedLength: Int
    public var confidence: Confidence
    public var reasons: [Reason]

    public init(phase: CyclePhase, cycleDay: Int, expectedLength: Int, confidence: Confidence, reasons: [Reason] = []) {
        self.phase = phase
        self.cycleDay = cycleDay
        self.expectedLength = expectedLength
        self.confidence = confidence
        self.reasons = reasons
    }

    /// The baseline window of the phase, or `nil` when the phase is unknown.
    public var baselineWindow: CycleBaselineWindow? {
        switch phase {
        case .menstrual, .follicular: .follicular
        case .luteal, .lateLuteal: .luteal
        case .ovulatory, .unknown: nil
        }
    }

    /// The baseline window when the estimate is confident enough for a rule to use it.
    public var usableWindow: CycleBaselineWindow? {
        confidence == .high ? baselineWindow : nil
    }
}
