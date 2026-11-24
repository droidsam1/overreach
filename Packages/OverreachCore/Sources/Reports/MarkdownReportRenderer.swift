import Analytics
import Domain
import Foundation

/// Renders a `TrainingReport` as Markdown for sharing with ChatGPT or Claude.
///
/// The output is in English with SI units so any model reads it the same way. Missing values are shown as
/// "–" so the model can tell "no data" apart from zero.
public enum MarkdownReportRenderer {
    public static func render(_ report: TrainingReport, calendar: Calendar = .current) -> String {
        let sections: [[String]] = [
            header(report, calendar: calendar),
            athleteContext(report),
            today(report),
            dailyTrends(report),
            sessions(report),
            runs(report, calendar: calendar),
            checkIns(report),
            question(report),
        ]
        return sections
            .filter { !$0.isEmpty }
            .map { $0.joined(separator: "\n") }
            .joined(separator: "\n\n") + "\n"
    }

    // MARK: - Sections

    private static func header(_ report: TrainingReport, calendar: Calendar) -> [String] {
        [
            "# Overreach training report",
            "",
            "Generated: \(CalendarDay(report.generatedAt, calendar: calendar)). "
                + "Numbers are computed by the app; please interpret them, do not recompute them. "
                + "This is training data, not medical data.",
        ]
    }

    private static func athleteContext(_ report: TrainingReport) -> [String] {
        guard let context = report.athleteContext, !context.isEmpty else { return [] }
        return ["## Athlete context", "", context]
    }

    private static func today(_ report: TrainingReport) -> [String] {
        var lines = ["## Today", ""]
        if let readiness = report.readiness {
            if !readiness.reasons.contains(where: { $0.isPrivateCheckInContext && !$0.isContext }) {
                lines.append("- Readiness: **\(readiness.level.rawValue)**")
            }
            for reason in readiness.reasons where !reason.isPrivateCheckInContext {
                let source = ReadinessRules.evidenceURL(for: reason).map { " ([research source](\($0.absoluteString)))" } ?? ""
                lines.append("  - \(describe(reason, hrvCoverage: readiness.hrvCoverage))\(source)")
            }
            if let coverage = readiness.hrvCoverage, !coverage.canCompare {
                lines.append("  - HRV comparison\(seriesNote(coverage.metric)) skipped. "
                    + "Recent readings available: \(coverage.recentReadings) (minimum \(coverage.minimumRecentReadings)). "
                    + "Baseline readings available: \(coverage.baselineReadings) (minimum \(coverage.minimumBaselineReadings)).")
            }
            if !readiness.inputs.isEmpty {
                lines.append("  - Inputs read by the rule:")
                lines += readiness.inputs.map { "    - \(describe($0))" }
            }
        }
        if let today = report.today {
            lines.append("- HRV last night: \(format(today.hrvNightlyAverageMs, decimals: 0)) ms\(statisticSuffix(today.hrvMetric)) "
                + "(watch-reported range \(format(today.hrvBaselineLowMs, decimals: 0))–"
                + "\(format(today.hrvBaselineHighMs, decimals: 0)) ms)")
            lines.append("- Resting HR: \(format(today.restingHeartRate, decimals: 0)) bpm")
            lines.append("- Sleep: \(format(today.sleepSeconds.map { $0 / 3600 }, decimals: 1)) h")
            lines.append("- Body Battery (high): \(format(today.bodyBatteryHigh, decimals: 0))")
            if let status = today.trainingStatus {
                lines.append("- Training status (watch): \(status)")
            }
        }
        if report.readiness == nil && report.today == nil {
            lines.append("No data for today.")
        }
        return lines
    }

    private static func dailyTrends(_ report: TrainingReport) -> [String] {
        guard !report.recentDays.isEmpty else { return [] }
        var lines = [
            "## Daily trends",
            "",
            "| Day | HRV (ms) | Resting HR (bpm) | Sleep (h) | Body Battery | Stress | Acute load |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for day in report.recentDays.sorted(by: { $0.day > $1.day }) {
            let cells = [
                day.day.description,
                format(day.hrvNightlyAverageMs, decimals: 0) + statisticSuffix(day.hrvMetric),
                format(day.restingHeartRate, decimals: 0),
                format(day.sleepSeconds.map { $0 / 3600 }, decimals: 1),
                format(day.bodyBatteryHigh, decimals: 0),
                format(day.averageStress, decimals: 0),
                format(day.acuteLoad, decimals: 0),
            ]
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines
    }

    private static func sessions(_ report: TrainingReport) -> [String] {
        guard !report.recentSessions.isEmpty else { return [] }
        var lines = ["## Recent strength sessions", ""]
        for session in report.recentSessions.sorted(by: { $0.day > $1.day }) {
            let muscles = session.effectiveSets
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue) \(format($0.value, decimals: 1))" }
                .joined(separator: ", ")
            lines.append("- \(session.day) — \(session.name): \(format(session.tonnageKg, decimals: 0)) kg; "
                + "effective sets: \(muscles.isEmpty ? "–" : muscles)")
            for adjustment in session.rotationAdjustments {
                lines.append("  - " + rotationAdjustment(adjustment))
            }
        }
        return lines
    }

    private static func rotationAdjustment(_ adjustment: RotationAdjustment.Outcome) -> String {
        let reason: String? = switch adjustment.reason {
        case .runCarryover: "residual fatigue from the recorded run"
        case .readiness: "reduced readiness"
        case .heavyLegsBeforeRun: "heavy leg training before the run"
        case .other: "other"
        case nil: nil
        }
        var detail = ["Rotation \(adjustment.action.rawValue)"]
        if let carryover = adjustment.carryover { detail.append("run carry-over \(carryover.rawValue)") }
        if let reason { detail.append(reason) }
        if let cap = adjustment.maximumRPE { detail.append("maximum RPE \(format(cap, decimals: 1))") }
        return detail.joined(separator: " · ")
    }

    private static func runs(_ report: TrainingReport, calendar: Calendar) -> [String] {
        guard !report.recentRuns.isEmpty else { return [] }
        var lines = ["## Recent runs", ""]
        for run in report.recentRuns.sorted(by: { $0.startedAt > $1.startedAt }) {
            lines.append("- \(CalendarDay(run.startedAt, calendar: calendar)): "
                + "\(format(run.distanceMeters / 1000, decimals: 1)) km in "
                + "\(format(run.durationSeconds / 60, decimals: 0)) min, "
                + "pace \(formatPace(run.paceSecondsPerKm)), "
                + "avg HR \(format(run.averageHeartRate, decimals: 0)) bpm, "
                + "load \(format(run.trainingLoad, decimals: 0))"
                + movement(run))
        }
        return lines
    }

    /// The watch's run/walk split, laps and moving time, only for what the source recorded (ADR-0043).
    private static func movement(_ run: RunActivity) -> String {
        var parts: [String] = []
        let part = { (name: String, part: RunWalkSplits.Part?) in
            guard let part, part.distanceMeters > 0 else { return }
            parts.append("\(name) \(format(part.distanceMeters / 1000, decimals: 2)) km in "
                + "\(format(part.durationSeconds / 60, decimals: 0)) min")
        }
        part("running", run.runWalk?.running)
        part("walking", run.runWalk?.walking)
        if run.runWalk != nil, run.longestContinuousRunMeters > 0 {
            parts.append("longest continuous run \(format(run.longestContinuousRunMeters / 1000, decimals: 2)) km")
        }
        if let pace = run.runningPaceSecondsPerKm { parts.append("running pace \(formatPace(pace))") }
        if let moving = run.movingDurationSeconds, moving.isFinite, moving > 0 {
            parts.append("moving \(format(moving / 60, decimals: 0)) min")
        }
        if let laps = run.lapCount, laps > 0 { parts.append("\(laps) laps") }
        return parts.isEmpty ? "" : "; " + parts.joined(separator: ", ")
    }

    private static func checkIns(_ report: TrainingReport) -> [String] {
        guard !report.checkIns.isEmpty else { return [] }
        var lines = ["## Check-ins", ""]
        for checkIn in report.checkIns.sorted(by: { $0.day > $1.day }) {
            var parts: [String] = []
            if checkIn.isSick { parts.append("sick") }
            if let energy = checkIn.energy { parts.append("energy \(energy)/5") }
            if let soreness = checkIn.soreness { parts.append("soreness \(soreness)/3") }
            if let note = checkIn.note, !note.isEmpty { parts.append("note: \(note)") }
            lines.append("- \(checkIn.day): \(parts.isEmpty ? "–" : parts.joined(separator: "; "))")
        }
        return lines
    }

    private static func question(_ report: TrainingReport) -> [String] {
        guard let question = report.question, !question.isEmpty else { return [] }
        return ["## Question", "", question]
    }

    // MARK: - Formatting

    static func format(_ value: Double?, decimals: Int) -> String {
        guard let value, value.isFinite else { return "–" }
        return String(format: "%.\(decimals)f", value)
    }

    static func formatPace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite, secondsPerKm > 0 else { return "–" }
        let total = Int(secondsPerKm.rounded())
        let seconds = total % 60
        return "\(total / 60):\(seconds < 10 ? "0" : "")\(seconds) /km"
    }

    /// " RMSSD": the statistic behind a displayed HRV value, which is never unlabelled (ADR-0025).
    static func statisticSuffix(_ metric: HRVMetric?) -> String {
        metric.map { " \($0.rawValue.uppercased())" } ?? ""
    }

    /// One input of the readiness rule: series and source, status, recent coverage, reference and outcome
    /// (ADR-0032).
    static func describe(_ audit: ReadinessInputAudit) -> String {
        let label = inputLabel(audit.input)
        let source = audit.source.map { " from \(sourceName($0))" } ?? ""
        var parts = [label.name + source + ": " + statusText(audit.status)]
        if let latest = audit.latestDay, audit.status != .compared || audit.recentDays > 1 {
            parts.append("latest \(latest)")
        }
        if let value = audit.value, !label.unit.isEmpty {
            let kind = audit.recentDays > 1 ? "recent mean" : "today"
            parts.append("\(kind) \(format(value, decimals: label.decimals)) \(label.unit)")
        }
        if audit.recentDays > 1, audit.status != .anotherSeriesUsed {
            parts.append("\(audit.recentReadings) usable readings in the last \(audit.recentDays) days")
        }
        if let reference = audit.reference {
            parts.append(describe(reference, label: label))
        }
        if audit.rejectedReadings > 0 {
            parts.append("\(audit.rejectedReadings) implausible readings ignored")
        }
        if let outcome = audit.outcome {
            parts.append("\(outcome.rawValue) the reference")
        }
        return parts.joined(separator: "; ")
    }

    private struct InputLabel {
        var name: String
        var unit: String
        var decimals: Int
    }

    private static func inputLabel(_ input: ReadinessInput) -> InputLabel {
        switch input {
        case .hrv(let series?):
            InputLabel(
                name: "HRV (\(series.metric.rawValue.uppercased()), \(series.window.rawValue))", unit: "ms", decimals: 0
            )
        case .hrv(nil): InputLabel(name: "HRV", unit: "ms", decimals: 0)
        case .restingHeartRate: InputLabel(name: "Resting HR", unit: "bpm", decimals: 0)
        case .sleep: InputLabel(name: "Sleep", unit: "h", decimals: 1)
        case .checkIn: InputLabel(name: "Check-in", unit: "", decimals: 0)
        }
    }

    private static func describe(_ reference: ReadinessReference, label: InputLabel) -> String {
        let (value, unit) = (format(reference.value, decimals: label.decimals), label.unit)
        switch reference.kind {
        case .fixedThreshold:
            return "threshold \(value) \(unit)"
        case .personalBaseline, .cyclePhase:
            let kind = if case .cyclePhase(let window) = reference.kind {
                "\(window.rawValue) baseline"
            } else {
                "baseline"
            }
            var text = "\(kind) \(value) \(unit) from \(reference.readings) readings over \(reference.days) days "
                + "(minimum \(reference.minimumReadings))"
            if reference.overlappingReadings > 0 {
                text += ", \(reference.overlappingReadings) of them inside the recent window"
            }
            return text
        }
    }

    private static func statusText(_ status: ReadinessInputStatus) -> String {
        switch status {
        case .compared: "compared"
        case .missing: "no data"
        case .stale: "no recent data, not used"
        case .outOfRange: "only implausible values, not used"
        case .buildingBaseline: "baseline still building, not used"
        case .tooFewRecent: "too few recent readings, not used"
        case .anotherSeriesUsed: "not used, another HRV series was judged"
        }
    }

    private static func sourceName(_ source: DataSourceKind) -> String {
        switch source {
        case .garmin: "Garmin"
        case .appleHealth: "Apple Health"
        case .manual: "the athlete"
        case .app: "Overreach"
        case .strongImport: "Strong import"
        }
    }

    /// " (RMSSD, Garmin)": which HRV series the rule judged (ADR-0025).
    static func seriesNote(_ metric: HRVMetric?) -> String {
        guard let metric else { return "" }
        return " (\(metric.rawValue.uppercased()), \(sourceName(metric.source)))"
    }

    static func describe(_ reason: ReadinessReason, hrvCoverage: HRVCoverage?) -> String {
        switch reason {
        case .markedSick:
            "Marked as sick in today's check-in"
        case .symptomsLimitTraining, .exerciseWarningSigns, .runningPainLimitsTraining, .unusualFatigue, .unusualStress:
            "Private check-in context"
        case .hrvBelowBaseline(let nights):
            if let coverage = hrvCoverage {
                "HRV\(seriesNote(coverage.metric)) below its normal range (\(nights) of \(coverage.recentReadings) "
                    + "comparable readings low in the last \(coverage.recentDays) days)"
            } else {
                "HRV below its normal range for \(nights) night\(nights == 1 ? "" : "s")"
            }
        case .hrvMayReflectCycle:
            "Low HRV may be the normal drop in the second half of the menstrual cycle (not counted towards red)"
        case let .phaseBaseline(window, cycles):
            "Compared with the \(window.rawValue) days of the last \(cycles) cycles (phase-aware baseline)"
        case .possibleLutealShift:
            "Resting HR slightly up; the threshold allows for the usual rise before a period (not counted)"
        case .restingHeartRateElevated(let bpm):
            "Resting HR \(format(bpm, decimals: 0)) bpm above baseline"
        case .shortSleep(let hours):
            "Short sleep: \(format(hours, decimals: 1)) h"
        case .lowEnergy(let score):
            "Low energy in today's check-in (\(score)/5)"
        case .highSoreness(let score):
            "Sore muscles in today's check-in (\(score)/3)"
        case .missingData:
            "Some data is missing"
        }
    }
}
