import Analytics
import Domain
import Foundation
import PresentationKit

/// A dated run planned more than 10% over the longest run of its previous 30 days (ADR-0043), with the offer to
/// shorten it. A warning, never a block: the run can be saved as planned.
public struct SessionCeilingNotice: Hashable, Sendable {
    public let explanation: ExplainedLine
    /// "Shorten to 11 km".
    public let shortenTitle: String
    /// The draft at the ceiling; saving it is the user's choice.
    public let shortened: RunningCalendarDraft

    init(_ warning: SessionCeiling.Warning, draft: RunningCalendarDraft, format: Format = .init()) {
        let km = { (meters: Int) in format.number(Double(meters) / 1_000, maxFractionDigits: 1) }
        let text = warning.isEstimated
            ? L10n.format(
                "At your recent pace this is about {1} km, more than 10% over your longest run of the previous 30 days "
                    + "({2} km). Single runs past that were linked to more overuse injuries.",
                km(warning.plannedMeters), km(warning.longestMeters)
            )
            : L10n.format(
                "{1} km is more than 10% over your longest run of the previous 30 days ({2} km). Single runs past "
                    + "that were linked to more overuse injuries.",
                km(warning.plannedMeters), km(warning.longestMeters)
            )
        explanation = ExplainedLine(text: text, evidence: SessionCeiling.evidence)
        shortenTitle = L10n.format("Shorten to {1} km", km(warning.ceilingMeters))
        shortened = draft.shortened(to: warning)
    }
}

extension RunningCalendarDraft {
    /// The same run at the ceiling: a distance becomes the ceiling and a duration shrinks in proportion.
    func shortened(to warning: SessionCeiling.Warning) -> Self {
        var copy = self
        let ratio = warning.plannedMeters > 0 ? Double(warning.ceilingMeters) / Double(warning.plannedMeters) : 1
        if distanceKm > 0 {
            copy.distanceKm = Double(warning.ceilingMeters) / 1_000
        }
        if minutes > 0 {
            copy.minutes = max(1, Int((Double(minutes) * ratio).rounded(.down)))
        }
        return copy
    }
}

extension PlanModel {
    /// Warnings for the upcoming dated runs, keyed by entry.
    var sessionCeilingWarnings: [UUID: SessionCeiling.Warning] {
        SessionCeiling.warnings(
            schedule: profile.goal?.scheduledRuns ?? [], runs: recentRuns,
            today: CalendarDay(clock(), calendar: calendar), calendar: calendar
        )
    }

    /// The warning for a run being edited, with the rest of the calendar as it would be after saving it.
    public func sessionCeilingNotice(for draft: RunningCalendarDraft) -> SessionCeilingNotice? {
        guard draft.showsWorkoutDetails, !draft.postponed, draft.completion == nil else { return nil }
        let entry = draft.entry(calendar: calendar)
        let schedule = (profile.goal?.scheduledRuns ?? []).filter { $0.id != entry.id } + [entry]
        let warning = SessionCeiling.warnings(
            schedule: schedule, runs: recentRuns, today: CalendarDay(clock(), calendar: calendar), calendar: calendar
        )[entry.id]
        return warning.map { SessionCeilingNotice($0, draft: draft) }
    }
}
