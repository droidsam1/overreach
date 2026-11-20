import Domain
import Foundation

/// Evidence behind the daily readiness light. Keys match entries in `docs/evidence.md` (ADR-0012, ADR-0020).
public enum ReadinessEvidence {
    /// 7-day rolling HRV against a personal normal range (HRV-guided training meta-analyses, 2020–2021).
    public static let hrv = EvidenceReference(key: "readiness-hrv", level: .moderate)
    /// RMSSD and SDNN are not interchangeable: each is its own series and baseline (ADR-0024, ADR-0025).
    public static let hrvMetrics = EvidenceReference(key: "hrv-metrics", level: .strong)
    /// Resting HR rises with short-term overload but inconsistently (Bosquet et al. 2008).
    public static let restingHeartRate = EvidenceReference(key: "readiness-resting-hr", level: .limited)
    /// Acute sleep loss lowers performance, endurance more than strength (Craven et al. 2022).
    public static let sleep = EvidenceReference(key: "readiness-sleep", level: .moderate)
    /// Self-reported well-being tracks training load better than common objective markers (Saw et al. 2016).
    public static let subjective = EvidenceReference(key: "readiness-subjective", level: .moderate)
    public static let reportedSymptoms = EvidenceReference(key: "readiness-reported-symptoms", level: .limited)
    /// Vagally mediated HRV is lower in the luteal than the follicular phase (Schmalenberger et al. 2019).
    public static let cyclePhase = EvidenceReference(key: "hrv-cycle-phase", level: .moderate)
    /// Resting HR rises and RMSSD falls in the luteal window, so a confident estimate compares like with like
    /// (wearable HRV living review, Sports Med 2025; Alzueta et al. 2022). Windows and thresholds are heuristics.
    public static let cyclePhaseBaselines = EvidenceReference(key: "cycle-phase-baselines", level: .moderate)
    /// Calendar counting gives coarse windows only (Bull et al. 2019; Elliott-Sale et al. 2021).
    public static let cyclePhaseEstimation = EvidenceReference(key: "cycle-phase-estimation", level: .moderate)
    /// Hormonal contraception and menopause keep the overall baseline (Stone et al. 2026).
    public static let hormonalContraception = EvidenceReference(key: "cycle-hormonal-contraception", level: .limited)
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
        /// Luteal window without a phase baseline: resting HR must rise this many bpm (`cycle-phase-baselines`).
        public var lutealRestingHeartRateRise: Double
        /// Previous cycles with data in the same window needed for a phase baseline.
        public var minimumPhaseBaselineCycles: Int
        /// Furthest back a phase baseline looks, in days.
        public var maximumPhaseBaselineDays: Int

        public init(
            baselineDays: Int = 60, minimumBaselineNights: Int = 14,
            rollingDays: Int = 7, minimumRollingNights: Int = 3,
            hrvBandStandardDeviations: Double = 0.5, restingHeartRateRise: Double = 5, shortSleepHours: Double = 6,
            lowEnergy: Int = 2, highSoreness: Int = 3, redSignals: Int = 2,
            lutealRestingHeartRateRise: Double = 8, minimumPhaseBaselineCycles: Int = 2,
            maximumPhaseBaselineDays: Int = 120
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
            self.lutealRestingHeartRateRise = lutealRestingHeartRateRise
            self.minimumPhaseBaselineCycles = minimumPhaseBaselineCycles
            self.maximumPhaseBaselineDays = maximumPhaseBaselineDays
        }
    }

    /// - Parameters:
    ///   - history: merged daily metrics, in any order. Days after `today` are ignored.
    ///   - checkIn: today's check-in, if the user filled it in.
    ///   - tracksNaturalCycle: the person tracks a natural menstrual cycle but no cycle data is passed: low HRV is
    ///     then reported with the cycle as a possible cause and is not a physiological signal for red.
    ///   - cycle: menstrual events and tracking mode. With a natural cycle and a high-confidence estimate, HRV and
    ///     resting HR are compared with the same window of previous cycles (`cycle-phase-baselines`).
    public static func readiness(
        today: CalendarDay, history: [DailyMetrics], checkIn: CheckIn?, settings: Settings = Settings(),
        tracksNaturalCycle: Bool = false, cycle: CycleContext? = nil, calendar: Calendar = .current
    ) -> Readiness {
        let checkIn = checkIn.flatMap { $0.day == today ? $0 : nil }
        if checkIn?.isSick == true {
            return Readiness(level: .red, reasons: [.markedSick])
        }
        if checkIn?.context == CheckIn.Context(question: .symptoms, answer: .yes) {
            return Readiness(level: .red, reasons: [.symptomsLimitTraining])
        }

        let byDay = Dictionary(history.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let baselineDays = (1...max(settings.baselineDays, 1)).map { today.adding(days: -$0, calendar: calendar) }
        let rollingDays = (0..<max(settings.rollingDays, 1)).map { today.adding(days: -$0, calendar: calendar) }
        let tracksNaturalCycle = tracksNaturalCycle || cycle?.mode == .naturalCycle
        // Only a high-confidence estimate is used by a rule (`cycle-phase-estimation`).
        let window = cycle?.estimate(on: today, calendar: calendar)?.usableWindow
        let phase = cycle.flatMap { phaseDays(today: today, cycle: $0, settings: settings, calendar: calendar) }

        var signals = Signals()
        let hrv = judgeHRV(
            byDay: byDay, baselineDays: baselineDays, rollingDays: rollingDays, phase: phase, window: window,
            tracksNaturalCycle: tracksNaturalCycle, settings: settings, into: &signals
        )
        judgeRestingHeartRate(
            today: today, byDay: byDay, baselineDays: baselineDays, phase: phase, window: window, settings: settings,
            into: &signals
        )
        var reasons = signals.reasons
        let physiological = signals.physiological
        var evaluated = signals.evaluated

        if let sleep = byDay[today]?.sleepSeconds {
            evaluated = true
            let hours = sleep / 3_600
            if hours < settings.shortSleepHours {
                reasons.append(.shortSleep(hours: hours))
            }
        }

        if let checkIn {
            evaluated = evaluated || checkIn.energy != nil || checkIn.soreness != nil || checkIn.context == nil
            if let energy = checkIn.energy, energy <= settings.lowEnergy {
                reasons.append(.lowEnergy(score: energy))
            }
            if let soreness = checkIn.soreness, soreness >= settings.highSoreness {
                reasons.append(.highSoreness(score: soreness))
            }
        }

        if let phase, let cycles = signals.phaseCycles.min() {
            reasons.append(.phaseBaseline(window: phase.window, cycles: cycles))
        }

        guard evaluated else {
            return Readiness(level: .unknown, reasons: [.missingData], hrvCoverage: hrv?.coverage)
        }
        if reasons.allSatisfy(\.isContext) {
            return Readiness(level: .green, reasons: reasons, hrvCoverage: hrv?.coverage)
        }
        // With a natural cycle, low HRV is context: neither it nor its note counts as a signal for red.
        let cycleContext = reasons.contains(.hrvMayReflectCycle)
        let signalCount = reasons.filter { reason in
            if reason.isContext { return false }
            if case .hrvBelowBaseline = reason { return !cycleContext }
            return true
        }.count
        if signalCount >= settings.redSignals && physiological > 0 {
            return Readiness(level: .red, reasons: reasons, hrvCoverage: hrv?.coverage)
        }
        return Readiness(level: .amber, reasons: reasons, hrvCoverage: hrv?.coverage)
    }

    /// The evidence behind one reason, to show next to it.
    public static func evidence(for reason: ReadinessReason) -> EvidenceReference {
        switch reason {
        case .markedSick: PlanEvidence.illness
        case .symptomsLimitTraining: ReadinessEvidence.reportedSymptoms
        case .hrvBelowBaseline: ReadinessEvidence.hrv
        case .hrvMayReflectCycle: ReadinessEvidence.cyclePhase
        case .phaseBaseline, .possibleLutealShift: ReadinessEvidence.cyclePhaseBaselines
        case .restingHeartRateElevated: ReadinessEvidence.restingHeartRate
        case .shortSleep: ReadinessEvidence.sleep
        case .lowEnergy, .highSoreness: ReadinessEvidence.subjective
        case .missingData: ReadinessEvidence.combination
        }
    }

    /// A representative source from the evidence register for the reason, shared by Today and reports.
    public static func evidenceURL(for reason: ReadinessReason) -> URL? {
        let address: String
        switch reason {
        case .markedSick, .symptomsLimitTraining: address = "https://doi.org/10.1136/bjsports-2022-105759"
        case .hrvBelowBaseline: address = "https://doi.org/10.3390/ijerph181910299"
        case .hrvMayReflectCycle: address = "https://doi.org/10.3390/jcm8111946"
        case .phaseBaseline: address = "https://doi.org/10.1007/s40279-025-02388-y"
        case .possibleLutealShift: address = "https://doi.org/10.2147/IJWH.S341917"
        case .restingHeartRateElevated: address = "https://pubmed.ncbi.nlm.nih.gov/18308872/"
        case .shortSleep: address = "https://doi.org/10.1007/s40279-022-01706-y"
        case .lowEnergy, .highSoreness: address = "https://pubmed.ncbi.nlm.nih.gov/26423706/"
        case .missingData: return nil
        }
        return URL(string: address)
    }

    /// Decide what is worth asking, without inferring stress or illness from the device (`readiness-context-prompt`).
    public static func contextQuestion(for readiness: Readiness) -> CheckIn.Context.Question? {
        var hasLowHRV = false
        var hasElevatedPulse = false
        for reason in readiness.reasons {
            switch reason {
            case .markedSick, .symptomsLimitTraining: return nil
            case .hrvBelowBaseline: hasLowHRV = true
            case .restingHeartRateElevated: hasElevatedPulse = true
            default: break
            }
        }
        guard hasLowHRV else { return nil }
        return hasElevatedPulse ? .symptoms : .stress
    }

    /// Each statistic is its own series (RMSSD and SDNN are not interchangeable, `hrv-metrics`, ADR-0025). The rule
    /// judges one series and never mixes or converts them: RMSSD when both can be compared, as Garmin's whole-night
    /// RMSSD is the better-supported input (`wearable-hrv-validity`); otherwise the one that can. When neither can,
    /// the coverage of the series read most recently (the watch being worn) says how many nights are still needed.
    ///
    /// With `required` (phase baselines), only a series that passes it and can be compared is judged; otherwise the
    /// result is `nil` so the caller falls back to the overall baseline.
    private static func hrvCheck(
        byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay], rollingDays: [CalendarDay], settings: Settings,
        required: ((HRVMetric) -> Bool)? = nil
    ) -> (coverage: HRVCoverage, lowNights: Int?)? {
        let series = HRVMetric.allCases.compactMap {
            hrvSeries($0, byDay: byDay, baselineDays: baselineDays, rollingDays: rollingDays, settings: settings)
        }
        let chosen: (coverage: HRVCoverage, baseline: [Double], recent: [Double])?
        if let required {
            chosen = series.first { $0.coverage.canCompare && $0.coverage.metric.map(required) == true }
        } else {
            chosen = series.first { $0.coverage.canCompare }
                ?? series.max { $0.coverage.latestDay < $1.coverage.latestDay }
        }
        guard let chosen else { return nil }
        guard chosen.coverage.canCompare else { return (chosen.coverage, nil) }
        let lowerBound = mean(chosen.baseline) - settings.hrvBandStandardDeviations * standardDeviation(chosen.baseline)
        guard mean(chosen.recent) < lowerBound else { return (chosen.coverage, nil) }
        return (chosen.coverage, chosen.recent.filter { $0 < lowerBound }.count)
    }

    /// One statistic's ln values and coverage, or `nil` when it has no reading in the rolling window.
    private static func hrvSeries(
        _ metric: HRVMetric, byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay],
        rollingDays: [CalendarDay], settings: Settings
    ) -> (coverage: HRVCoverage, baseline: [Double], recent: [Double])? {
        let latest = rollingDays.first { validHRV(byDay[$0]?.hrv(metric)) != nil }
        guard let latest else { return nil }
        let logHRV = { (days: [CalendarDay]) -> [Double] in
            days.compactMap { validHRV(byDay[$0]?.hrv(metric)) }.map { log($0) }
        }
        let baseline = logHRV(baselineDays)
        let recent = logHRV(rollingDays)
        let coverage = HRVCoverage(
            metric: metric, latestDay: latest,
            recentDays: rollingDays.count, recentReadings: recent.count,
            minimumRecentReadings: max(settings.minimumRollingNights, 1),
            baselineDays: baselineDays.count, baselineReadings: baseline.count,
            minimumBaselineReadings: max(settings.minimumBaselineNights, 1)
        )
        return (coverage, baseline, recent)
    }

    /// What the HRV and resting-HR checks found, before sleep and the check-in are added.
    private struct Signals {
        var reasons: [ReadinessReason] = []
        var physiological = 0
        var evaluated = false
        /// Previous cycles behind each phase baseline used.
        var phaseCycles: [Int] = []
    }

    /// HRV against the same window of previous cycles when there is enough, otherwise against the overall baseline.
    private static func judgeHRV(
        byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay], rollingDays: [CalendarDay], phase: PhaseDays?,
        window: CycleBaselineWindow?, tracksNaturalCycle: Bool, settings: Settings, into signals: inout Signals
    ) -> (coverage: HRVCoverage, lowNights: Int?)? {
        var phaseHRV: (coverage: HRVCoverage, lowNights: Int?)?
        if let phase {
            let cycles = { (metric: HRVMetric) in phase.cycles { validHRV(byDay[$0]?.hrv(metric)) != nil } }
            phaseHRV = hrvCheck(
                byDay: byDay, baselineDays: phase.days, rollingDays: rollingDays, settings: settings
            ) { cycles($0) >= settings.minimumPhaseBaselineCycles }
            if let metric = phaseHRV?.coverage.metric { signals.phaseCycles.append(cycles(metric)) }
            // The phase baseline's readings come from the whole span looked back over, not consecutive days.
            phaseHRV = phaseHRV.map { (spanning($0.coverage, days: phase.span), $0.lowNights) }
        }
        // Garmin's own HRV range is whole-cycle; the rule compares with personal series only, so it stays context.
        let hrv = phaseHRV
            ?? hrvCheck(byDay: byDay, baselineDays: baselineDays, rollingDays: rollingDays, settings: settings)
        guard let hrv, hrv.coverage.canCompare else { return hrv }
        signals.evaluated = true
        guard let lowNights = hrv.lowNights else { return hrv }
        signals.reasons.append(.hrvBelowBaseline(nights: lowNights))
        // Against the same window of previous cycles, or in a confident follicular window, low HRV counts.
        if phaseHRV == nil && tracksNaturalCycle && window != .follicular {
            signals.reasons.append(.hrvMayReflectCycle)
        } else {
            signals.physiological += 1
        }
        return hrv
    }

    /// Resting HR against the same window of previous cycles when there is enough; otherwise against the overall
    /// baseline, with a wider threshold in a confident luteal window.
    private static func judgeRestingHeartRate(
        today: CalendarDay, byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay], phase: PhaseDays?,
        window: CycleBaselineWindow?, settings: Settings, into signals: inout Signals
    ) {
        guard let todayResting = byDay[today]?.restingHeartRate else { return }
        let phaseResting = phase?.days.compactMap { byDay[$0]?.restingHeartRate } ?? []
        let phaseCycles = phase?.cycles { byDay[$0]?.restingHeartRate != nil } ?? 0
        let usesPhase = phaseResting.count >= settings.minimumBaselineNights
            && phaseCycles >= settings.minimumPhaseBaselineCycles
        let baseline = usesPhase ? phaseResting : baselineDays.compactMap { byDay[$0]?.restingHeartRate }
        guard baseline.count >= settings.minimumBaselineNights else { return }
        signals.evaluated = true
        if usesPhase { signals.phaseCycles.append(phaseCycles) }
        let widened = !usesPhase && window == .luteal
        let threshold = widened ? settings.lutealRestingHeartRateRise : settings.restingHeartRateRise
        let rise = todayResting - mean(baseline)
        if rise >= threshold {
            signals.reasons.append(.restingHeartRateElevated(bpmAboveBaseline: rise))
            signals.physiological += 1
        } else if widened && rise >= settings.restingHeartRateRise {
            signals.reasons.append(.possibleLutealShift)
        }
    }

    /// Previous days in today's baseline window, each with the start of its cycle (`cycle-phase-baselines`).
    struct PhaseDays {
        var window: CycleBaselineWindow
        var days: [CalendarDay]
        var cycleStart: [CalendarDay: CalendarDay]
        /// Calendar days looked back over.
        var span: Int

        /// Distinct cycles with at least one day passing `hasData`.
        func cycles(where hasData: (CalendarDay) -> Bool) -> Int {
            Set(days.filter(hasData).compactMap { cycleStart[$0] }).count
        }
    }

    /// Days of previous cycles whose own estimate, with the events known then, was confident and in today's window.
    /// Looks back over the readiness baseline period, extended to cover the previous cycles needed (at most 120 days).
    static func phaseDays(
        today: CalendarDay, cycle: CycleContext, settings: Settings, calendar: Calendar
    ) -> PhaseDays? {
        guard let estimate = cycle.estimate(on: today, calendar: calendar), let window = estimate.usableWindow else {
            return nil
        }
        let currentStart = today.adding(days: -(estimate.cycleDay - 1), calendar: calendar)
        let previousStarts = CyclePhaseEstimator.cycleStarts(events: cycle.events, calendar: calendar)
            .filter { $0 < currentStart }
        let wanted = previousStarts.suffix(max(settings.minimumPhaseBaselineCycles, 1)).first
        let reach = wanted.map { CyclePhaseEstimator.days(from: $0, to: today, calendar: calendar) } ?? 0
        let lookback = max(min(max(reach, settings.baselineDays), settings.maximumPhaseBaselineDays), 1)

        var days: [CalendarDay] = []
        var cycleStart: [CalendarDay: CalendarDay] = [:]
        for offset in 1...lookback {
            let day = today.adding(days: -offset, calendar: calendar)
            guard day < currentStart, let past = cycle.estimate(on: day, calendar: calendar),
                  past.usableWindow == window else { continue }
            days.append(day)
            cycleStart[day] = day.adding(days: -(past.cycleDay - 1), calendar: calendar)
        }
        return PhaseDays(window: window, days: days, cycleStart: cycleStart, span: lookback)
    }

    private static func spanning(_ coverage: HRVCoverage, days: Int) -> HRVCoverage {
        HRVCoverage(
            metric: coverage.metric, latestDay: coverage.latestDay, recentDays: coverage.recentDays,
            recentReadings: coverage.recentReadings, minimumRecentReadings: coverage.minimumRecentReadings,
            baselineDays: days, baselineReadings: coverage.baselineReadings,
            minimumBaselineReadings: coverage.minimumBaselineReadings
        )
    }

    private static func validHRV(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
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
