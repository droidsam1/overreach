import Analytics
import Domain
import Foundation
import PresentationKit
import TrainingServices

/// "Sleep and training times" in Recovery (ADR-0045, docs/design/circadian-timing.md): usual clock times and the
/// observations the analysis returns, each with its evidence level. Observations, never a diagnosis, and no time of
/// day is ranked above another.
public struct SleepTimingCard: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    public struct Observation: Hashable, Sendable, Identifiable {
        public let text: String
        public let evidenceText: String
        public var id: String { text }
    }

    public let rows: [Row]
    /// A sleep summary when the available nights show a steady schedule.
    public let summary: String?
    public let observations: [Observation]
    public let footnote: String

    /// `nil` until there are enough nights (or sessions) for usual times (`CircadianTiming.Settings`).
    public init?(_ report: CircadianTiming.Report, format: Format = Format()) {
        var rows: [Row] = []
        if let bedtime = report.usualBedtime {
            rows.append(Row(label: L10n.text("Usual bedtime"), value: Self.clock(bedtime, format: format)))
        }
        if let wake = report.usualWake {
            rows.append(Row(label: L10n.text("Usual wake time"), value: Self.clock(wake, format: format)))
        }
        if let spread = report.midpointSpread {
            rows.append(Row(
                label: L10n.text("Sleep midpoint variation"),
                value: L10n.format("{1} min", String(Int(spread.rounded())))
            ))
        }
        if let training = report.usualTrainingStart {
            rows.append(Row(label: L10n.text("Usual training start"), value: Self.clock(training, format: format)))
        }
        if let spread = report.trainingSpread {
            rows.append(Row(
                label: L10n.text("Training start time variation"),
                value: L10n.format("{1} min", String(Int(spread.rounded())))
            ))
        }
        guard !rows.isEmpty else { return nil }
        self.rows = rows
        observations = report.insights.compactMap { insight in
            guard let text = Self.text(insight, format: format) else { return nil }
            return Observation(
                text: text,
                evidenceText: L10n.format("Evidence: {1}", insight.evidence.level.displayName)
            )
        }
        let irregularSleep = report.insights.contains { insight in
            if case .irregularSleep = insight { return true }
            return false
        }
        summary = report.midpointSpread != nil && !irregularSleep
            ? L10n.text("Your sleep schedule looked steady on the nights with recorded times.")
            : nil
        footnote = L10n.format(
            "Last {1} days: {2} nights with bed and wake times, {3} sessions with start and end times.",
            String(SleepTrainingTiming.windowDays), String(report.nights), String(report.sessions)
        )
    }

    static func text(_ insight: CircadianTiming.Insight, format: Format) -> String? {
        switch insight {
        case let .irregularSleep(index?, _):
            L10n.format(
                "Your sleep and wake times shift from night to night (regularity {1} of 100). Regular sleep and "
                    + "wake times go with lower long-term health risk, whatever your training.",
                String(index)
            )
        case let .irregularSleep(nil, spread):
            L10n.format(
                "The middle of your sleep shifts by about {1} from night to night. Regular sleep and wake times go "
                    + "with lower long-term health risk, whatever your training.",
                duration(spread, format: format)
            )
        case let .socialJetlag(minutes):
            L10n.format(
                "On weekends you sleep about {1} later than on weekdays. Weekends stand in for days off, so shift "
                    + "work can make this misleading.",
                duration(minutes, format: format)
            )
        case .variableTrainingTime:
            nil
        case let .hardSessionsNearBed(count, total):
            L10n.format(
                "{1} of {2} hard sessions ended less than an hour before your usual bedtime. Finishing about 2 h "
                    + "earlier, or keeping those sessions easier, protects sleep.",
                String(count), String(total)
            )
        }
    }

    /// "45 min", "2 h" or "1 h 30 min", rounded to 5 minutes.
    static func duration(_ minutes: Int, format: Format) -> String {
        let rounded = max(5, Int((Double(minutes) / 5).rounded()) * 5)
        let hours = rounded / 60
        let rest = rounded % 60
        if hours == 0 { return L10n.format("{1} min", String(rest)) }
        if rest == 0 { return L10n.format("{1} h", String(hours)) }
        return L10n.format("{1} h {2} min", String(hours), String(rest))
    }

    /// A clock time in the user's locale ("23:10", "11:10 PM") from minutes after midnight.
    static func clock(_ minutes: Double, format: Format) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let whole = Int(minutes.rounded()) % 1_440
        let date = Date(timeIntervalSince1970: Double(whole) * 60)
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(format.locale)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
