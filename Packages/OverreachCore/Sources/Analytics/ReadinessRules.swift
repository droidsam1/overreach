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
    /// Plausible ranges, measurement protocol and staleness of the inputs (ADR-0032): data-quality defaults.
    public static let inputQuality = EvidenceReference(key: "readiness-input-quality", level: .heuristic)
}

/// The daily traffic light (ADR-0020): today's HRV, resting HR, sleep and check-in against the person's own
/// baseline. Pure function; every threshold is in `Settings`. `Readiness.inputs` records what each input
/// contributed (ADR-0032).
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
        /// Nightly HRV outside this range, in ms, is a measurement error and is ignored (`readiness-input-quality`).
        public var plausibleHRVMs: ClosedRange<Double>
        /// Resting HR outside this range, in bpm, is ignored.
        public var plausibleRestingHeartRate: ClosedRange<Double>
        /// Sleep longer than this many hours is ignored; zero or less is no measurement.
        public var maximumSleepHours: Double

        public init(
            baselineDays: Int = 60, minimumBaselineNights: Int = 14,
            rollingDays: Int = 7, minimumRollingNights: Int = 3,
            hrvBandStandardDeviations: Double = 0.5, restingHeartRateRise: Double = 5, shortSleepHours: Double = 6,
            lowEnergy: Int = 2, highSoreness: Int = 3, redSignals: Int = 2,
            lutealRestingHeartRateRise: Double = 8, minimumPhaseBaselineCycles: Int = 2,
            maximumPhaseBaselineDays: Int = 120, plausibleHRVMs: ClosedRange<Double> = 3...300,
            plausibleRestingHeartRate: ClosedRange<Double> = 25...150, maximumSleepHours: Double = 18
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
            self.plausibleHRVMs = plausibleHRVMs
            self.plausibleRestingHeartRate = plausibleRestingHeartRate
            self.maximumSleepHours = maximumSleepHours
        }
    }

    /// - Parameters:
    ///   - history: merged daily metrics, in any order. Days after `today` are ignored.
    ///   - checkIn: the latest check-in, if any. Only a check-in from `today` counts; an older one is reported as
    ///     stale in `Readiness.inputs` and never answers for today.
    ///   - tracksNaturalCycle: the person tracks a natural menstrual cycle but no cycle data is passed: low HRV is
    ///     then reported with the cycle as a possible cause and is not a physiological signal for red.
    ///   - cycle: menstrual events and tracking mode. With a natural cycle and a high-confidence estimate, HRV and
    ///     resting HR are compared with the same window of previous cycles (`cycle-phase-baselines`).
    public static func readiness(
        today: CalendarDay, history: [DailyMetrics], checkIn: CheckIn?, settings: Settings = Settings(),
        tracksNaturalCycle: Bool = false, cycle: CycleContext? = nil, calendar: Calendar = .current
    ) -> Readiness {
        let latestCheckIn = checkIn
        let checkIn = checkIn.flatMap { $0.day == today ? $0 : nil }

        let byDay = Dictionary(
            history.filter { $0.day <= today }.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let baselineDays = (1...max(settings.baselineDays, 1)).map { today.adding(days: -$0, calendar: calendar) }
        let rollingDays = (0..<max(settings.rollingDays, 1)).map { today.adding(days: -$0, calendar: calendar) }
        let tracksNaturalCycle = tracksNaturalCycle || cycle?.mode == .naturalCycle
        // Only a high-confidence estimate is used by a rule (`cycle-phase-estimation`).
        let window = cycle?.estimate(on: today, calendar: calendar)?.usableWindow
        let phase = cycle.flatMap { phaseDays(today: today, cycle: $0, settings: settings, calendar: calendar) }

        let inputs = Inputs(
            today: today, byDay: byDay, baselineDays: baselineDays, rollingDays: rollingDays, phase: phase,
            window: window, settings: settings
        )
        var signals = Signals()
        let hrv = judgeHRV(inputs, tracksNaturalCycle: tracksNaturalCycle, into: &signals)
        judgeRestingHeartRate(inputs, into: &signals)
        judgeSleep(inputs, into: &signals)
        signals.audits.append(checkInAudit(latest: latestCheckIn, today: today))
        let result = { (level: ReadinessLevel, reasons: [ReadinessReason]) in
            Readiness(level: level, reasons: reasons, hrvCoverage: hrv?.coverage, inputs: signals.audits)
        }

        if checkIn?.isSick == true {
            return result(.red, [.markedSick])
        }
        if checkIn?.context == CheckIn.Context(question: .symptoms, answer: .yes) {
            return result(.red, [.symptomsLimitTraining])
        }

        var reasons = signals.reasons
        var evaluated = signals.evaluated
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

        guard evaluated else { return result(.unknown, [.missingData]) }
        if reasons.allSatisfy(\.isContext) { return result(.green, reasons) }
        // With a natural cycle, low HRV is context: neither it nor its note counts as a signal for red.
        let cycleContext = reasons.contains(.hrvMayReflectCycle)
        let signalCount = reasons.filter { reason in
            if reason.isContext { return false }
            if case .hrvBelowBaseline = reason { return !cycleContext }
            return true
        }.count
        if signalCount >= settings.redSignals && signals.physiological > 0 { return result(.red, reasons) }
        return result(.amber, reasons)
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

    // MARK: - HRV

    /// One HRV series' ln values and coverage over the windows the rule reads.
    private struct HRVSeries {
        var id: HRVSeriesID
        /// Latest day with a usable reading, in the recent window or the baseline days.
        var latestDay: CalendarDay?
        var baseline: [Double]
        var recent: [Double]
        /// Baseline readings taken on a day of the recent window.
        var overlap: Int
        /// Implausible readings ignored, in both windows.
        var rejected: Int
        /// `nil` when the series has no usable reading in the recent window.
        var coverage: HRVCoverage?

        var canCompare: Bool { coverage?.canCompare == true }
    }

    /// Each statistic and reading window is its own series: RMSSD and SDNN are not interchangeable (`hrv-metrics`,
    /// ADR-0025), and readings from sleep and from the day are different protocols (ADR-0032). Readings outside
    /// `Settings.plausibleHRVMs` are ignored and counted.
    private static func hrvSeries(
        _ id: HRVSeriesID, byDay: [CalendarDay: DailyMetrics], baselineDays: [CalendarDay],
        rollingDays: [CalendarDay], settings: Settings
    ) -> HRVSeries {
        let raw = { (day: CalendarDay) -> Double? in
            guard let metrics = byDay[day], metrics.hrvWindow(id.metric) == id.window else { return nil }
            return metrics.hrv(id.metric)
        }
        let usable = { (day: CalendarDay) -> Double? in
            raw(day).flatMap { isPlausible($0, in: settings.plausibleHRVMs) ? $0 : nil }
        }
        let recentDays = Set(rollingDays)
        let allDays = recentDays.union(baselineDays)
        let baselineWithValues = baselineDays.filter { usable($0) != nil }
        let recent = rollingDays.compactMap(usable).map { log($0) }
        let coverage = rollingDays.first { usable($0) != nil }.map { latest in
            HRVCoverage(
                metric: id.metric, window: id.window, latestDay: latest,
                recentDays: rollingDays.count, recentReadings: recent.count,
                minimumRecentReadings: max(settings.minimumRollingNights, 1),
                baselineDays: baselineDays.count, baselineReadings: baselineWithValues.count,
                minimumBaselineReadings: max(settings.minimumBaselineNights, 1)
            )
        }
        return HRVSeries(
            id: id, latestDay: allDays.filter { usable($0) != nil }.max(),
            baseline: baselineWithValues.compactMap(usable).map { log($0) }, recent: recent,
            overlap: baselineWithValues.filter { recentDays.contains($0) }.count,
            rejected: allDays.filter { raw($0) != nil && usable($0) == nil }.count, coverage: coverage
        )
    }

    /// The rule judges one series and never mixes or converts them: the first of `HRVSeriesID.all` that can be
    /// compared, as Garmin's whole-night RMSSD is the better-supported input (`wearable-hrv-validity`). When none
    /// can, the coverage of the series read most recently (the watch being worn) says how many nights are still
    /// needed.
    private static func chooseSeries(_ series: [HRVSeries]) -> HRVSeries? {
        let current = series.filter { $0.coverage != nil }
        if let comparable = current.first(where: \.canCompare) { return comparable }
        return current.max { lhs, rhs in
            guard let left = lhs.coverage?.latestDay, let right = rhs.coverage?.latestDay else { return false }
            return left < right
        }
    }

    /// HRV against the same window of previous cycles when there is enough, otherwise against the overall baseline.
    private static func judgeHRV(
        _ inputs: Inputs, tracksNaturalCycle: Bool, into signals: inout Signals
    ) -> (coverage: HRVCoverage, lowNights: Int?)? {
        let (byDay, rollingDays, settings) = (inputs.byDay, inputs.rollingDays, inputs.settings)
        let overall = HRVSeriesID.all.map {
            hrvSeries($0, byDay: byDay, baselineDays: inputs.baselineDays, rollingDays: rollingDays, settings: settings)
        }
        var chosen: HRVSeries?
        var reference = ReadinessReference.Kind.personalBaseline
        var referenceDays = inputs.baselineDays.count
        if let phase = inputs.phase {
            let cycles = { (id: HRVSeriesID) in
                phase.cycles { day in
                    guard let metrics = byDay[day], metrics.hrvWindow(id.metric) == id.window,
                          let value = metrics.hrv(id.metric) else { return false }
                    return isPlausible(value, in: settings.plausibleHRVMs)
                }
            }
            let phaseSeries = HRVSeriesID.all.map {
                hrvSeries($0, byDay: byDay, baselineDays: phase.days, rollingDays: rollingDays, settings: settings)
            }
            if var found = phaseSeries.first(where: {
                $0.canCompare && cycles($0.id) >= settings.minimumPhaseBaselineCycles
            }) {
                signals.phaseCycles.append(cycles(found.id))
                // The phase baseline's readings come from the whole span looked back over, not consecutive days.
                found.coverage = found.coverage.map { spanning($0, days: phase.span) }
                chosen = found
                reference = .cyclePhase(phase.window)
                referenceDays = phase.span
            }
        }
        // Garmin's own HRV range is whole-cycle; the rule compares with personal series only, so it stays context.
        let usedPhase = chosen != nil
        chosen = chosen ?? chooseSeries(overall)

        var lowNights: Int?
        var outcome: ReadinessComparison?
        if let chosen, chosen.canCompare {
            signals.evaluated = true
            let center = mean(chosen.baseline)
            let band = settings.hrvBandStandardDeviations * standardDeviation(chosen.baseline)
            let recentMean = mean(chosen.recent)
            if recentMean < center - band {
                outcome = .below
                // The denominator is the recent window's eligible measured nights.
                lowNights = chosen.recent.filter { $0 < center - band }.count
            } else {
                outcome = recentMean > center + band ? .above : .within
            }
        }

        signals.audits += hrvAudits(
            overall: overall, chosen: chosen, outcome: outcome,
            reference: (reference, referenceDays), settings: settings
        )

        guard let chosen, let coverage = chosen.coverage else { return nil }
        guard let lowNights else { return (coverage, nil) }
        signals.reasons.append(.hrvBelowBaseline(nights: lowNights))
        // Against the same window of previous cycles, or in a confident follicular window, low HRV counts.
        if !usedPhase && tracksNaturalCycle && inputs.window != .follicular {
            signals.reasons.append(.hrvMayReflectCycle)
        } else {
            signals.physiological += 1
        }
        return (coverage, lowNights)
    }

    /// One audit per HRV series with data: the one judged first, then the others in preference order. Without
    /// any reading in the baseline period, a single `.hrv(nil)` entry says HRV is missing.
    private static func hrvAudits(
        overall: [HRVSeries], chosen: HRVSeries?, outcome: ReadinessComparison?,
        reference: (kind: ReadinessReference.Kind, days: Int), settings: Settings
    ) -> [ReadinessInputAudit] {
        var audits: [ReadinessInputAudit] = []
        let recentDays = max(settings.rollingDays, 1)
        if let chosen, let coverage = chosen.coverage {
            let status: ReadinessInputStatus = if coverage.canCompare {
                .compared
            } else if coverage.baselineReadings < coverage.minimumBaselineReadings {
                .buildingBaseline
            } else {
                .tooFewRecent
            }
            audits.append(ReadinessInputAudit(
                input: .hrv(chosen.id), status: status, source: chosen.id.metric.source,
                latestDay: chosen.latestDay, value: chosen.recent.isEmpty ? nil : exp(mean(chosen.recent)),
                recentDays: coverage.recentDays, recentReadings: coverage.recentReadings,
                rejectedReadings: chosen.rejected,
                reference: ReadinessReference(
                    kind: reference.kind, days: reference.days, readings: coverage.baselineReadings,
                    minimumReadings: coverage.minimumBaselineReadings, overlappingReadings: chosen.overlap,
                    value: chosen.baseline.isEmpty ? nil : exp(mean(chosen.baseline))
                ),
                outcome: outcome
            ))
        }
        for series in overall where series.id != chosen?.id {
            let status: ReadinessInputStatus
            if series.coverage != nil {
                status = .anotherSeriesUsed
            } else if series.latestDay != nil {
                status = .stale
            } else if series.rejected > 0 {
                status = .outOfRange
            } else {
                continue
            }
            audits.append(ReadinessInputAudit(
                input: .hrv(series.id), status: status, source: series.id.metric.source, latestDay: series.latestDay,
                recentDays: recentDays, recentReadings: series.recent.count, rejectedReadings: series.rejected
            ))
        }
        if audits.isEmpty {
            audits.append(ReadinessInputAudit(input: .hrv(nil), status: .missing, recentDays: recentDays))
        }
        return audits
    }

    // MARK: - Resting HR, sleep and check-in

    /// Resting HR against the same window of previous cycles when there is enough; otherwise against the overall
    /// baseline, with a wider threshold in a confident luteal window. Only today's value is judged.
    private static func judgeRestingHeartRate(_ inputs: Inputs, into signals: inout Signals) {
        let (byDay, phase, settings) = (inputs.byDay, inputs.phase, inputs.settings)
        let range = settings.plausibleRestingHeartRate
        let usable = { (day: CalendarDay) -> Double? in
            byDay[day]?.restingHeartRate.flatMap { isPlausible($0, in: range) ? $0 : nil }
        }
        let read = [inputs.today] + inputs.baselineDays
        let rejected = read.filter { byDay[$0]?.restingHeartRate != nil && usable($0) == nil }.count
        let latestDay = read.first { usable($0) != nil }
        let audit = { (status: ReadinessInputStatus, reference: ReadinessReference?, outcome: ReadinessComparison?) in
            ReadinessInputAudit(
                input: .restingHeartRate, status: status,
                source: latestDay.flatMap { byDay[$0]?.restingHeartRateOrigin }, latestDay: latestDay,
                value: usable(inputs.today), recentReadings: usable(inputs.today) == nil ? 0 : 1,
                rejectedReadings: rejected, reference: reference, outcome: outcome
            )
        }
        guard let todayResting = usable(inputs.today) else {
            let status: ReadinessInputStatus = if byDay[inputs.today]?.restingHeartRate != nil {
                .outOfRange
            } else {
                latestDay == nil ? .missing : .stale
            }
            signals.audits.append(audit(status, nil, nil))
            return
        }

        let phaseResting = phase?.days.compactMap(usable) ?? []
        let phaseCycles = phase?.cycles { usable($0) != nil } ?? 0
        let usesPhase = phaseResting.count >= settings.minimumBaselineNights
            && phaseCycles >= settings.minimumPhaseBaselineCycles
        let baseline = usesPhase ? phaseResting : inputs.baselineDays.compactMap(usable)
        let reference = { (value: Double?) in
            ReadinessReference(
                kind: usesPhase ? phase.map { .cyclePhase($0.window) } ?? .personalBaseline : .personalBaseline,
                days: usesPhase ? phase?.span ?? 0 : inputs.baselineDays.count, readings: baseline.count,
                minimumReadings: settings.minimumBaselineNights, value: value
            )
        }
        guard baseline.count >= settings.minimumBaselineNights else {
            signals.audits.append(audit(.buildingBaseline, reference(nil), nil))
            return
        }
        signals.evaluated = true
        if usesPhase { signals.phaseCycles.append(phaseCycles) }
        let widened = !usesPhase && inputs.window == .luteal
        let threshold = widened ? settings.lutealRestingHeartRateRise : settings.restingHeartRateRise
        let rise = todayResting - mean(baseline)
        let outcome: ReadinessComparison = rise >= threshold ? .above : (rise <= -threshold ? .below : .within)
        signals.audits.append(audit(.compared, reference(mean(baseline)), outcome))
        if rise >= threshold {
            signals.reasons.append(.restingHeartRateElevated(bpmAboveBaseline: rise))
            signals.physiological += 1
        } else if widened && rise >= settings.restingHeartRateRise {
            signals.reasons.append(.possibleLutealShift)
        }
    }

    /// Last night's sleep against the fixed short-sleep threshold. An earlier night never stands in for it.
    private static func judgeSleep(_ inputs: Inputs, into signals: inout Signals) {
        let settings = inputs.settings
        let usable = { (day: CalendarDay) -> Double? in
            guard let seconds = inputs.byDay[day]?.sleepSeconds, seconds.isFinite, seconds > 0,
                  seconds / 3_600 <= settings.maximumSleepHours else { return nil }
            return seconds / 3_600
        }
        let rejected = inputs.rollingDays.filter { inputs.byDay[$0]?.sleepSeconds != nil && usable($0) == nil }.count
        let latestDay = inputs.rollingDays.first { usable($0) != nil }
        let hours = usable(inputs.today)
        let status: ReadinessInputStatus = if hours != nil {
            .compared
        } else if inputs.byDay[inputs.today]?.sleepSeconds != nil {
            .outOfRange
        } else {
            latestDay == nil ? .missing : .stale
        }
        let outcome: ReadinessComparison? = hours.map { $0 < settings.shortSleepHours ? .below : .within }
        signals.audits.append(ReadinessInputAudit(
            input: .sleep, status: status, source: latestDay.flatMap { inputs.byDay[$0]?.sleepOrigin },
            latestDay: latestDay, value: hours, recentReadings: hours == nil ? 0 : 1, rejectedReadings: rejected,
            reference: hours == nil ? nil : ReadinessReference(
                kind: .fixedThreshold, days: 0, readings: 0, minimumReadings: 0, value: settings.shortSleepHours
            ),
            outcome: outcome
        ))
        guard let hours else { return }
        signals.evaluated = true
        if hours < settings.shortSleepHours {
            signals.reasons.append(.shortSleep(hours: hours))
        }
    }

    /// Whether today's check-in exists. An older one is stale: it never answers for today.
    private static func checkInAudit(latest: CheckIn?, today: CalendarDay) -> ReadinessInputAudit {
        guard let latest else { return ReadinessInputAudit(input: .checkIn, status: .missing) }
        let isToday = latest.day == today
        return ReadinessInputAudit(
            input: .checkIn, status: isToday ? .compared : .stale, source: .manual, latestDay: latest.day,
            recentReadings: isToday ? 1 : 0
        )
    }

    // MARK: - Shared

    /// What the HRV, resting-HR and sleep checks found, before the check-in is added.
    private struct Signals {
        var reasons: [ReadinessReason] = []
        var physiological = 0
        var evaluated = false
        /// Previous cycles behind each phase baseline used.
        var phaseCycles: [Int] = []
        var audits: [ReadinessInputAudit] = []
    }

    /// What the HRV and resting-HR checks compare.
    private struct Inputs {
        var today: CalendarDay
        var byDay: [CalendarDay: DailyMetrics]
        var baselineDays: [CalendarDay]
        var rollingDays: [CalendarDay]
        /// Previous days in today's baseline window, with a high-confidence estimate.
        var phase: PhaseDays?
        /// Today's baseline window, with a high-confidence estimate.
        var window: CycleBaselineWindow?
        var settings: Settings
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
            metric: coverage.metric, window: coverage.window, latestDay: coverage.latestDay,
            recentDays: coverage.recentDays, recentReadings: coverage.recentReadings,
            minimumRecentReadings: coverage.minimumRecentReadings, baselineDays: days,
            baselineReadings: coverage.baselineReadings, minimumBaselineReadings: coverage.minimumBaselineReadings
        )
    }

    private static func isPlausible(_ value: Double, in range: ClosedRange<Double>) -> Bool {
        value.isFinite && range.contains(value)
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
