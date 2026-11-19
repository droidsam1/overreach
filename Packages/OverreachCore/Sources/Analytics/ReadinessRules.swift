import Domain
import Foundation

/// Evidence behind the daily readiness light. Keys match entries in `docs/evidence.md` (ADR-0012, ADR-0020).
public enum ReadinessEvidence {
    /// 7-day rolling HRV against a personal normal range (HRV-guided training meta-analyses, 2020–2021).
    public static let hrv = EvidenceReference(key: "readiness-hrv", level: .moderate)
    /// Resting HR rises with short-term overload but inconsistently (Bosquet et al. 2008).
    public static let restingHeartRate = EvidenceReference(key: "readiness-resting-hr", level: .limited)
    /// Acute sleep loss lowers performance, endurance more than strength (Craven et al. 2022).
    public static let sleep = EvidenceReference(key: "readiness-sleep", level: .moderate)
    /// Self-reported well-being tracks training load better than common objective markers (Saw et al. 2016).
    public static let subjective = EvidenceReference(key: "readiness-subjective", level: .moderate)
    /// How signals combine into green, amber and red: coaching defaults.
    public static let combination = EvidenceReference(key: "readiness-combination", level: .heuristic)
}

/// The daily traffic light (ADR-0020): today's HRV, resting HR, sleep and check-in against the person's own
/// baseline. Pure function; every threshold is in `Settings`.
public enum ReadinessRules {
    public struct Settings: Hashable, Sendable {
        /// Days before today used for the personal baselines.
        public var baselineDays: Int
        /// Nights with a value needed before a baseline is trusted.
        public var minimumBaselineNights: Int
        /// Nights (today included) averaged for the HRV trend.
        public var rollingDays: Int
        /// Nights with a value needed in the rolling window.
        public var minimumRollingNights: Int
        /// Half-width of the normal HRV range, in standard deviations of the baseline (ln values).
        public var hrvBandStandardDeviations: Double
        /// Resting HR this many bpm above the baseline counts as a signal.
        public var restingHeartRateRise: Double
        /// Sleep below this many hours counts as a signal.
        public var shortSleepHours: Double
        /// Check-in energy (1–5) at or below this counts as a signal.
        public var lowEnergy: Int
        /// Check-in soreness (0–3) at or above this counts as a signal.
        public var highSoreness: Int
        /// Signals needed for red, when at least one of them is HRV or resting HR.
        public var redSignals: Int

        public init(
            baselineDays: Int = 60, minimumBaselineNights: Int = 14,
            rollingDays: Int = 7, minimumRollingNights: Int = 3,
            hrvBandStandardDeviations: Double = 0.5, restingHeartRateRise: Double = 5, shortSleepHours: Double = 6,
            lowEnergy: Int = 2, highSoreness: Int = 3, redSignals: Int = 2
        ) {
            self.baselineDays = baselineDays
            self.minimumBaselineNights = minimumBaselineNights
            self.rollingDays = rollingDays
            self.minimumRollingNights = minimumRollingNights
            self.hrvBandStandardDeviations = hrvBandStandardDeviations
            self.restingHeartRateRise = restingHeartRateRise
            self.shortSleepHours = shortSleepHours
            self.lowEnergy = lowEnergy
            self.highSoreness = highSoreness
            self.redSignals = redSignals
        }
    }

    /// - Parameters:
    ///   - history: merged daily metrics, in any order. Days after `today` are ignored.
    ///   - checkIn: today's check-in, if the user filled it in.
    public static func readiness(
        today: CalendarDay, history: [DailyMetrics], checkIn: CheckIn?, settings: Settings = Settings(),
        calendar: Calendar = .current
    ) -> Readiness {
        if checkIn?.isSick == true {
            return Readiness(level: .red, reasons: [.markedSick])
        }

        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let baselineDays = (1...max(settings.baselineDays, 1)).map { today.adding(days: -$0, calendar: calendar) }
        let rollingDays = (0..<max(settings.rollingDays, 1)).map { today.adding(days: -$0, calendar: calendar) }

        var reasons: [ReadinessReason] = []
        var physiological = 0
        var evaluated = false

        if let hrv = hrvCheck(byDay: byDay, baselineDays: baselineDays, rollingDays: rollingDays, settings: settings) {
            evaluated = true
            if let lowNights = hrv {
                reasons.append(.hrvBelowBaseline(nights: lowNights))
                physiological += 1
            }
        }

        let restingBaseline = baselineDays.compactMap { byDay[$0]?.restingHeartRate }
        if restingBaseline.count >= settings.minimumBaselineNights, let todayResting = byDay[today]?.restingHeartRate {
            evaluated = true
            let rise = todayResting - mean(restingBaseline)
            if rise >= settings.restingHeartRateRise {
                reasons.append(.restingHeartRateElevated(bpmAboveBaseline: rise))
                physiological += 1
            }
        }

        if let sleep = byDay[today]?.sleepSeconds {
            evaluated = true
            let hours = sleep / 3_600
            if hours < settings.shortSleepHours {
                reasons.append(.shortSleep(hours: hours))
            }
        }

        if let checkIn {
            evaluated = true
            if let energy = checkIn.energy, energy <= settings.lowEnergy {
                reasons.append(.lowEnergy(score: energy))
            }
            if let soreness = checkIn.soreness, soreness >= settings.highSoreness {
                reasons.append(.highSoreness(score: soreness))
            }
        }

        guard evaluated else { return Readiness(level: .unknown, reasons: [.missingData]) }
        if reasons.isEmpty { return Readiness(level: .green) }
        if reasons.count >= settings.redSignals && physiological > 0 {
            return Readiness(level: .red, reasons: reasons)
        }
        return Readiness(level: .amber, reasons: reasons)
    }

    /// The evidence behind one reason, to show next to it.
    public static func evidence(for reason: ReadinessReason) -> EvidenceReference {
        switch reason {
        case .markedSick: PlanEvidence.illness
        case .hrvBelowBaseline: ReadinessEvidence.hrv
        case .restingHeartRateElevated: ReadinessEvidence.restingHeartRate
        case .shortSleep: ReadinessEvidence.sleep
        case .lowEnergy, .highSoreness: ReadinessEvidence.subjective
        case .missingData: ReadinessEvidence.combination
        }
    }

    /// `nil` when HRV cannot be judged; `.some(nil)` when it is in range; `.some(n)` when the rolling average is
    /// below the normal range, with `n` the low nights in the window.
    static func hrvCheck(
        byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay], rollingDays: [CalendarDay], settings: Settings
    ) -> Int?? {
        let logHRV = { (days: [CalendarDay]) -> [Double] in
            days.compactMap { byDay[$0]?.hrvNightlyAverageMs }.filter { $0 > 0 }.map { log($0) }
        }
        let baseline = logHRV(baselineDays)
        let recent = logHRV(rollingDays)
        guard baseline.count >= settings.minimumBaselineNights, recent.count >= settings.minimumRollingNights else {
            return nil
        }
        let lowerBound = mean(baseline) - settings.hrvBandStandardDeviations * standardDeviation(baseline)
        guard mean(recent) < lowerBound else { return .some(nil) }
        return .some(recent.filter { $0 < lowerBound }.count)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let average = mean(values)
        return (values.map { ($0 - average) * ($0 - average) }.reduce(0, +) / Double(values.count - 1)).squareRoot()
    }
}
