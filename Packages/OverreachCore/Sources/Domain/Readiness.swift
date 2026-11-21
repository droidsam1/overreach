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
    /// The person tracks a natural cycle: low HRV may be the normal luteal-phase drop, so it is context and does
    /// not make the light red on its own (`hrv-cycle-phase`).
    case hrvMayReflectCycle
    case restingHeartRateElevated(bpmAboveBaseline: Double)
    /// HRV and/or resting HR were compared with the same window of previous cycles, not the whole-cycle baseline
    /// (`cycle-phase-baselines`). Context, not a signal.
    case phaseBaseline(window: CycleBaselineWindow, cycles: Int)
    /// Luteal window without a phase baseline yet: resting HR rose above the usual threshold but within the widened
    /// luteal one, so it is not counted (`cycle-phase-baselines`). Context, not a signal.
    case possibleLutealShift
    case shortSleep(hours: Double)
    /// Check-in energy, 1 (exhausted) … 5 (great).
    case lowEnergy(score: Int)
    /// Check-in muscle soreness, 0 (none) … 3 (very sore).
    case highSoreness(score: Int)
    case missingData

    /// Context that explains the comparison; never a signal for amber or red on its own.
    public var isContext: Bool {
        switch self {
        case .hrvMayReflectCycle, .phaseBaseline, .possibleLutealShift: true
        default: false
        }
    }
}

/// Coverage of the HRV series selected for readiness. Window lengths are calendar days.
public struct HRVCoverage: Hashable, Codable, Sendable {
    public let metric: HRVMetric?
    /// When the series' readings were taken. `nil` in data written before ADR-0032.
    public let window: HRVReadingWindow?
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
        metric: HRVMetric?, window: HRVReadingWindow? = nil, latestDay: CalendarDay, recentDays: Int,
        recentReadings: Int, minimumRecentReadings: Int, baselineDays: Int, baselineReadings: Int,
        minimumBaselineReadings: Int
    ) {
        self.metric = metric
        self.window = window
        self.latestDay = latestDay
        self.recentDays = recentDays
        self.recentReadings = recentReadings
        self.minimumRecentReadings = minimumRecentReadings
        self.baselineDays = baselineDays
        self.baselineReadings = baselineReadings
        self.minimumBaselineReadings = minimumBaselineReadings
    }
}

/// One HRV series: a statistic read with one protocol (ADR-0025, ADR-0032).
public struct HRVSeriesID: Hashable, Codable, Sendable {
    public let metric: HRVMetric
    public let window: HRVReadingWindow

    public init(_ metric: HRVMetric, _ window: HRVReadingWindow) {
        self.metric = metric
        self.window = window
    }

    /// Series in the order the rule prefers them: whole-night RMSSD, SDNN during sleep, daytime SDNN.
    public static let all: [HRVSeriesID] = [.init(.rmssd, .sleep), .init(.sdnn, .sleep), .init(.sdnn, .daytime)]
}

/// One input the readiness rule reads (ADR-0032).
public enum ReadinessInput: Hashable, Codable, Sendable {
    /// One HRV series; `nil` when no series had a reading in the baseline period.
    case hrv(HRVSeriesID?)
    case restingHeartRate
    case sleep
    case checkIn
}

/// What happened to one input today.
public enum ReadinessInputStatus: Hashable, Codable, Sendable {
    /// Compared with its reference; `ReadinessInputAudit.outcome` says how.
    case compared
    /// No usable value in the window the rule reads.
    case missing
    /// Values exist, but none recent enough: the latest one is `ReadinessInputAudit.latestDay`.
    case stale
    /// The only values in the window are outside the plausible range and were ignored.
    case outOfRange
    /// Too few earlier readings for a personal reference yet.
    case buildingBaseline
    /// Too few recent readings to judge a trend.
    case tooFewRecent
    /// Another HRV series was judged instead (ADR-0025).
    case anotherSeriesUsed
}

/// How a compared value relates to its reference.
public enum ReadinessComparison: String, Hashable, Codable, Sendable {
    case below, within, above
}

/// What a value is compared with.
public struct ReadinessReference: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        /// The person's own earlier days.
        case personalBaseline
        /// The same window of the person's previous cycles (`cycle-phase-baselines`).
        case cyclePhase(CycleBaselineWindow)
        /// A fixed threshold from the rule's settings, not a personal range.
        case fixedThreshold
    }

    public let kind: Kind
    /// Calendar days looked back over; 0 for a fixed threshold.
    public let days: Int
    public let readings: Int
    public let minimumReadings: Int
    /// Readings that are both in the reference and in the recent window (ADR-0032 keeps them in the baseline).
    public let overlappingReadings: Int
    /// Mean of the reference readings, or the fixed threshold, in the input's unit.
    public let value: Double?

    public init(
        kind: Kind, days: Int, readings: Int, minimumReadings: Int, overlappingReadings: Int = 0, value: Double?
    ) {
        self.kind = kind
        self.days = days
        self.readings = readings
        self.minimumReadings = minimumReadings
        self.overlappingReadings = overlappingReadings
        self.value = value
    }
}

/// Provenance, coverage, recency and outcome of one readiness input, so a decision can be audited (ADR-0032).
/// Values are in ms (HRV), bpm (resting HR), hours (sleep) or check-in points.
public struct ReadinessInputAudit: Hashable, Codable, Sendable {
    public let input: ReadinessInput
    public let status: ReadinessInputStatus
    public let source: DataSourceKind?
    /// Latest day with a usable value, today included.
    public let latestDay: CalendarDay?
    /// The value judged: the recent mean for HRV, today's value otherwise.
    public let value: Double?
    /// Calendar days in the recent window and usable readings in it.
    public let recentDays: Int
    public let recentReadings: Int
    /// Readings in the windows read that were outside the plausible range and ignored.
    public let rejectedReadings: Int
    public let reference: ReadinessReference?
    public let outcome: ReadinessComparison?

    public init(
        input: ReadinessInput, status: ReadinessInputStatus, source: DataSourceKind? = nil,
        latestDay: CalendarDay? = nil, value: Double? = nil, recentDays: Int = 1, recentReadings: Int = 0,
        rejectedReadings: Int = 0, reference: ReadinessReference? = nil, outcome: ReadinessComparison? = nil
    ) {
        self.input = input
        self.status = status
        self.source = source
        self.latestDay = latestDay
        self.value = value
        self.recentDays = recentDays
        self.recentReadings = recentReadings
        self.rejectedReadings = rejectedReadings
        self.reference = reference
        self.outcome = outcome
    }
}

/// The daily traffic light, always with its reasons.
public struct Readiness: Hashable, Codable, Sendable {
    public var level: ReadinessLevel
    public var reasons: [ReadinessReason]
    public var hrvCoverage: HRVCoverage?
    /// Every input the rule read, in a fixed order: HRV series, resting HR, sleep, check-in. Empty when the
    /// readiness was not computed by `ReadinessRules`.
    public var inputs: [ReadinessInputAudit]

    public init(
        level: ReadinessLevel, reasons: [ReadinessReason] = [], hrvCoverage: HRVCoverage? = nil,
        inputs: [ReadinessInputAudit] = []
    ) {
        self.level = level
        self.reasons = reasons
        self.hrvCoverage = hrvCoverage
        self.inputs = inputs
    }

    private enum CodingKeys: String, CodingKey {
        case level, reasons, hrvCoverage, inputs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(ReadinessLevel.self, forKey: .level)
        reasons = try container.decodeIfPresent([ReadinessReason].self, forKey: .reasons) ?? []
        hrvCoverage = try container.decodeIfPresent(HRVCoverage.self, forKey: .hrvCoverage)
        inputs = try container.decodeIfPresent([ReadinessInputAudit].self, forKey: .inputs) ?? []
    }

    /// The audit of the HRV series that was judged, or of the one read most recently when none could be.
    public var hrvInput: ReadinessInputAudit? {
        let series = inputs.filter { if case .hrv = $0.input { true } else { false } }
        return series.first { $0.status != .anotherSeriesUsed } ?? series.first
    }

    public func input(_ input: ReadinessInput) -> ReadinessInputAudit? {
        inputs.first { $0.input == input }
    }
}
