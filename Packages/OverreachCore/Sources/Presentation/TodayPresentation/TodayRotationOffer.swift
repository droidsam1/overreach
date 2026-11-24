import Analytics
import Domain
import Foundation
import PresentationKit

public struct TodayRotationOffer: Hashable, Sendable {
    public let title: String
    public let acceptTitle: String
    public let dismissTitle = L10n.text("Keep plan")
}

struct TodayRotationDecision {
    let suggestion: RotationAdjustment.Suggestion
    let carryover: RunCarryover.Assessment
    let next: RotationProjection.Session
    let partner: RotationProjection.Session?
    let run: RunActivity
    let previousLegs: RotationProjection.Session?
    let readiness: ReadinessLevel
    let now: Date
    let calendar: Calendar
    let format: Format

    var offer: TodayRotationOffer? {
        switch suggestion.action {
        case let .swap(heavy, lighter):
            guard let partner else { return nil }
            return TodayRotationOffer(
                title: L10n.format("After your run: do {1} today, {2} on {3}.",
                                   lighter.name, heavy.name, weekday(partner.day)),
                acceptTitle: L10n.text("Swap sessions")
            )
        case let .postpone(days):
            return TodayRotationOffer(
                title: L10n.format("After your run: move {1} to {2}.", next.slot.name,
                                   weekday(suggestion.day.adding(days: days, calendar: calendar))),
                acceptTitle: L10n.text("Postpone session")
            )
        case .keep, .keepCapped:
            return nil
        }
    }

    var explanation: [String] {
        let outcome: String
        switch suggestion.action {
        case .keep:
            outcome = L10n.format("Keep {1} as planned.", next.slot.name)
        case let .keepCapped(maxRPE):
            outcome = L10n.format("Keep {1} at the previous load and cap the targets at RPE {2}.",
                                  next.slot.name, format.number(maxRPE))
        case .swap, .postpone:
            outcome = offer?.title ?? ""
        }
        let unknown = L10n.text("Unknown")
        let hours = now.timeIntervalSince(run.startedAt.addingTimeInterval(run.durationSeconds)) / 3_600
        let previous = previousLegs.map { L10n.format("{1} on {2}", $0.slot.name, weekday($0.day)) } ?? unknown
        var details = [
            outcome,
            L10n.format("Run: {1} · {2} · {3} · {4} hours ago", run.name ?? L10n.text("Run"),
                        SessionReport.durationText(run.durationSeconds) ?? unknown, effort ?? unknown,
                        format.number(hours, maxFractionDigits: 1)),
            L10n.format("Elevation: {1}", elevation ?? unknown)
        ]
        if carryover.exposureUnknown { details.append(L10n.text("Recent running exposure is unknown.")) }
        details.append(contentsOf: [
            L10n.format("Previous leg session: {1}", previous),
            L10n.format("Readiness: {1} · {2}", readiness.displayName, suggestion.evidence.level.displayName)
        ])
        return details
    }

    private var effort: String? {
        run.aerobicTrainingEffect.map { L10n.format("Aerobic training effect {1}", format.number($0)) }
            ?? run.anaerobicTrainingEffect.map { L10n.format("Anaerobic training effect {1}", format.number($0)) }
            ?? run.averageHeartRate.map { L10n.format("{1} bpm", format.number($0, maxFractionDigits: 0)) }
    }

    private var elevation: String? {
        run.elevationLossMeters.map { L10n.format("{1} m descent", format.number($0, maxFractionDigits: 0)) }
            ?? run.elevationGainMeters.map { L10n.format("{1} m ascent", format.number($0, maxFractionDigits: 0)) }
    }

    private func weekday(_ day: CalendarDay) -> String {
        day.startDate(in: calendar).formatted(.dateTime.locale(format.locale).weekday(.wide))
    }
}
