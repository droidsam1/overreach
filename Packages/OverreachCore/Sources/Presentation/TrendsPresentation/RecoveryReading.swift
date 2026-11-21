import Analytics
import Domain
import Foundation
import PresentationKit

/// One recovery reading with what the athlete needs to judge it: the value, how it compares with their usual
/// range, and in the details where it came from, when it was taken and how many readings back it.
public struct RecoveryReading: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case hrv, restingHeartRate, sleep, bodyBattery, stress, vo2Max
    }

    public let kind: Kind
    public let title: String
    /// "46 ms", or a short "No reading" when there is none.
    public let value: String
    /// How the value compares with the usual range, or why it cannot be compared yet.
    public let summary: String
    /// Source, last update, coverage and baseline, one line each.
    public let details: [String]
    /// The reading is missing, stale or has no baseline yet. The view shows it as secondary.
    public let isAvailable: Bool

    public var id: Kind { kind }
}

/// Builds the recovery rows from the same audited inputs the readiness light uses (ADR-0032), so Today and
/// Recovery & Progress never disagree about a reading.
struct RecoveryReadings {
    let calendar: Calendar
    let format: Format

    func readings(readiness: Readiness, history: [DailyMetrics], today: CalendarDay) -> [RecoveryReading] {
        let audits = [
            readiness.hrvInput ?? ReadinessInputAudit(input: .hrv(nil), status: .missing),
            readiness.input(.restingHeartRate) ?? ReadinessInputAudit(input: .restingHeartRate, status: .missing),
            readiness.input(.sleep) ?? ReadinessInputAudit(input: .sleep, status: .missing),
        ]
        return audits.map(reading) + estimates(history: history, today: today)
    }

    private func reading(_ audit: ReadinessInputAudit) -> RecoveryReading {
        let (kind, title, unit): (RecoveryReading.Kind, String, String) = switch audit.input {
        case .hrv: (.hrv, seriesTitle(audit), "ms")
        case .restingHeartRate: (.restingHeartRate, L10n.text("Resting HR"), "bpm")
        case .sleep, .checkIn: (.sleep, L10n.text("Sleep"), "h")
        }
        let digits = kind == .sleep ? 1 : 0
        let hasValue = audit.value != nil && audit.status != .missing && audit.status != .outOfRange
        let value = audit.value.flatMap { hasValue ? format.number($0, maxFractionDigits: digits) + " " + unit : nil }
        return RecoveryReading(
            kind: kind, title: title, value: value ?? L10n.text("No reading"), summary: summary(audit, unit: unit),
            details: details(audit, unit: unit, digits: digits), isAvailable: hasValue
        )
    }

    private func seriesTitle(_ audit: ReadinessInputAudit) -> String {
        if case let .hrv(series?) = audit.input { return L10n.format("HRV ({1})", series.metric.seriesLabel) }
        return L10n.text("HRV")
    }

    private func summary(_ audit: ReadinessInputAudit, unit: String) -> String {
        switch audit.status {
        case .compared:
            switch audit.outcome {
            case .below: return L10n.text("Below your usual range")
            case .above: return L10n.text("Above your usual range")
            case .within, nil: return L10n.text("Within your usual range")
            }
        case .buildingBaseline:
            let reference = audit.reference
            return L10n.format(
                "Still building your usual range ({1} of {2} comparable readings needed)",
                String(reference?.readings ?? 0), String(reference?.minimumReadings ?? 0)
            )
        case .tooFewRecent:
            return L10n.format(
                "Too few recent readings to judge a trend ({1} in the last {2} days)",
                String(audit.recentReadings), String(audit.recentDays)
            )
        case .stale: return L10n.text("No recent reading")
        case .outOfRange: return L10n.text("Readings outside the plausible range were ignored")
        case .anotherSeriesUsed: return L10n.text("Another HRV series was compared instead")
        case .missing: return L10n.text("No reading yet. Connect a source to see it.")
        }
    }

    private func details(_ audit: ReadinessInputAudit, unit: String, digits: Int) -> [String] {
        var lines: [String] = []
        if let source = audit.source { lines.append(L10n.format("From {1}", source.displayName)) }
        if let latest = audit.latestDay {
            lines.append(L10n.format("Latest reading: {1}", dateText(latest)))
        }
        if audit.recentReadings > 0 || audit.status == .tooFewRecent {
            lines.append(L10n.format(
                "Coverage: {1} readings in the last {2} days", String(audit.recentReadings), String(audit.recentDays)
            ))
        }
        if let reference = audit.reference, let value = reference.value {
            let amount = format.number(value, maxFractionDigits: digits) + " " + unit
            switch reference.kind {
            case .fixedThreshold:
                lines.append(L10n.format("Reference: {1} (a fixed threshold)", amount))
            case .personalBaseline, .cyclePhase:
                lines.append(L10n.format(
                    "Usual: {1} over {2} days ({3} readings)", amount,
                    String(reference.days), String(reference.readings)
                ))
            }
        }
        if audit.rejectedReadings > 0 {
            lines.append(L10n.format("Ignored as implausible: {1} readings", String(audit.rejectedReadings)))
        }
        return lines
    }

    /// Garmin's scores and the watch's VO2max estimate. They are shown as estimates and never feed a rule.
    private func estimates(history: [DailyMetrics], today: CalendarDay) -> [RecoveryReading] {
        let recent = history.filter { $0.day <= today }.sorted { $0.day > $1.day }
        func latest(
            _ kind: RecoveryReading.Kind, _ title: String, _ value: KeyPath<DailyMetrics, Double?>, digits: Int,
            note: String
        ) -> RecoveryReading? {
            guard let entry = recent.first(where: { $0[keyPath: value] != nil }),
                  let number = entry[keyPath: value] else { return nil }
            let sources = DataSourceKind.allCases.filter(entry.sources.contains).map(\.displayName)
            var lines = [L10n.format("Latest reading: {1}", dateText(entry.day))]
            if !sources.isEmpty { lines.insert(L10n.format("From {1}", sources.joined(separator: " · ")), at: 0) }
            return RecoveryReading(
                kind: kind, title: title, value: format.number(number, maxFractionDigits: digits),
                summary: note, details: lines, isAvailable: true
            )
        }
        let garmin = L10n.text("Garmin's estimate")
        let watch = L10n.text("Watch estimate, follow the trend")
        return [
            latest(.bodyBattery, L10n.text("Body Battery"), \.bodyBatteryHigh, digits: 0, note: garmin),
            latest(.stress, L10n.text("Stress"), \.averageStress, digits: 0, note: garmin),
            latest(.vo2Max, L10n.text("VO2max"), \.vo2Max, digits: 1, note: watch),
        ].compactMap { $0 }
    }

    private func dateText(_ day: CalendarDay) -> String {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }
}
