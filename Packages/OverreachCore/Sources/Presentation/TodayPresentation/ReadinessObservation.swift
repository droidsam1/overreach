import Domain
import Foundation
import PresentationKit

public struct ReadinessObservation: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case supporting
        case context
        case unavailable
    }

    public let kind: Kind
    public let text: String
}

public struct ReadinessSourceDetail: Identifiable, Sendable {
    public let id: ReadinessInput
    public let title: String
    public let details: [String]

    init(audit: ReadinessInputAudit, calendar: Calendar, format: Format) {
        id = audit.input
        title = Self.title(for: audit.input)
        var details = [Self.status(for: audit)]
        if let source = audit.source, audit.input == .sleep || audit.input == .restingHeartRate {
            details.append(L10n.format("From {1}", source.displayName))
        }
        if let day = audit.latestDay {
            let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
            let date = day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
            details.append(L10n.format("Latest usable reading on {1}.", date))
        }
        if case .hrv = audit.input, audit.recentReadings > 0 {
            details.append(L10n.format(
                "{1} usable readings in the last {2} days.", audit.recentReadings, audit.recentDays
            ))
        }
        if let reference = audit.reference, reference.kind != .fixedThreshold {
            details.append(L10n.format(
                "Reference: {1} readings from the previous {2} days.", reference.readings, reference.days
            ))
        }
        self.details = details
    }

    private static func title(for input: ReadinessInput) -> String {
        switch input {
        case .hrv(let series?):
            let title = series.window == .sleep ? L10n.text("Sleep HRV") : L10n.text("Daytime HRV")
            return L10n.format("{1} ({2})", title, series.metric.seriesLabel)
        case .hrv(nil): return L10n.text("HRV")
        case .restingHeartRate: return L10n.text("Resting heart rate")
        case .sleep: return L10n.text("Sleep")
        case .checkIn: return L10n.text("Check-in")
        }
    }

    private static func comparison(for audit: ReadinessInputAudit) -> String {
        if audit.input == .checkIn { return L10n.text("Check-in available for today.") }
        if audit.input == .sleep {
            return audit.outcome == .below ? L10n.text("Below the short-sleep threshold.")
                : L10n.text("At or above the short-sleep threshold.")
        }
        switch audit.outcome {
        case .below: return L10n.text("Below your usual range.")
        case .within: return L10n.text("Within your usual range.")
        case .above: return L10n.text("Above your usual range.")
        case nil: return L10n.text("Compared with its reference.")
        }
    }

    private static func status(for audit: ReadinessInputAudit) -> String {
        switch audit.status {
        case .compared:
            comparison(for: audit)
        case .missing: L10n.text("No usable data.")
        case .stale: L10n.text("No recent reading.")
        case .outOfRange: L10n.text("Readings outside the plausible range.")
        case .buildingBaseline: L10n.text("Still building your baseline.")
        case .tooFewRecent: L10n.text("Too few recent readings.")
        case .anotherSeriesUsed: L10n.text("Another HRV series was used.")
        }
    }
}
