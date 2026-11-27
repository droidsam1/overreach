import Analytics
import Foundation

extension MarkdownReportRenderer {
    static func sleepTrainingTiming(_ report: CircadianTiming.Report?) -> [String] {
        guard let report else { return [] }
        let clocks = [
            ("Usual bedtime", report.usualBedtime),
            ("Usual wake time", report.usualWake),
            ("Usual training start", report.usualTrainingStart),
        ].compactMap { label, value in value.map { "- \(label) \(clockTime($0)) local time" } }
        guard !clocks.isEmpty || !report.insights.isEmpty else { return [] }

        let spreads = [
            ("Bedtime spread", report.bedtimeSpread),
            ("Wake time spread", report.wakeSpread),
            ("Sleep midpoint spread", report.midpointSpread),
            ("Training start spread", report.trainingSpread),
            ("Weekend minus weekday sleep midpoint", report.weekendShift),
        ].compactMap { label, value in value.map { "- \(label) \(format($0, decimals: 0)) min" } }
        var lines = [
            "## Sleep and training timing", "",
            "Coverage includes \(report.nights) nights and \(report.sessions) training sessions.", "",
        ] + clocks + spreads
        if let index = report.regularityIndex {
            lines.append("- Sleep Regularity Index \(format(index, decimals: 0)) out of 100")
        }
        lines += report.insights.map { "- \(timingObservation($0))" }
        return lines
    }

    private static func clockTime(_ minutes: Double) -> String {
        guard (0...1_440).contains(minutes) else { return "–" }
        let rounded = Int(minutes.rounded()) % 1_440
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    private static func timingObservation(_ insight: CircadianTiming.Insight) -> String {
        let text: String
        switch insight {
        case let .irregularSleep(index?, _):
            text = "Irregular sleep timing with a Sleep Regularity Index of \(index)."
        case let .irregularSleep(nil, spread):
            text = "Irregular sleep timing with a sleep midpoint spread of \(spread) min."
        case let .socialJetlag(minutes):
            text = "The sleep midpoint was \(minutes) min later on weekends."
        case let .variableTrainingTime(spread):
            text = "Training start times varied with a spread of \(spread) min."
        case let .hardSessionsNearBed(count, total):
            text = "\(count) of \(total) hard sessions ended close to the usual bedtime."
        }
        return "\(text) Evidence level \(insight.evidence.level.rawValue) (`\(insight.evidence.key)`)."
    }
}
