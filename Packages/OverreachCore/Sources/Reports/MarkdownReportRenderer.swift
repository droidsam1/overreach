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
            lines.append("- Readiness: **\(readiness.level.rawValue)**")
            for reason in readiness.reasons {
                let source = ReadinessRules.evidenceURL(for: reason).map { " ([research source](\($0.absoluteString)))" } ?? ""
                lines.append("  - \(describe(reason, hrvCoverage: readiness.hrvCoverage))\(source)")
            }
            if let coverage = readiness.hrvCoverage, !coverage.canCompare {
                lines.append("  - HRV comparison skipped. "
                    + "Recent readings available: \(coverage.recentReadings) (minimum \(coverage.minimumRecentReadings)). "
                    + "Baseline readings available: \(coverage.baselineReadings) (minimum \(coverage.minimumBaselineReadings)).")
            }
        }
        if let today = report.today {
            lines.append("- HRV last night: \(format(today.hrvNightlyAverageMs, decimals: 0)) ms "
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
                format(day.hrvNightlyAverageMs, decimals: 0),
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
        }
        return lines
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
                + "load \(format(run.trainingLoad, decimals: 0))")
        }
        return lines
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

    static func describe(_ reason: ReadinessReason, hrvCoverage: HRVCoverage?) -> String {
        switch reason {
        case .markedSick:
            "Marked as sick in today's check-in"
        case .symptomsLimitTraining:
            "Today's check-in says symptoms make training feel unsuitable"
        case .hrvBelowBaseline(let nights):
            if let coverage = hrvCoverage {
                "HRV below its normal range (\(nights) of \(coverage.recentReadings) comparable readings low "
                    + "in the last \(coverage.recentDays) days)"
            } else {
                "HRV below its normal range for \(nights) night\(nights == 1 ? "" : "s")"
            }
        case .hrvMayReflectCycle:
            "Low HRV may be the normal drop in the second half of the menstrual cycle (not counted towards red)"
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
