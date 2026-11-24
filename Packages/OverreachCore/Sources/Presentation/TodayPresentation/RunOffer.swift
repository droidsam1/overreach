import Analytics
import Domain
import Foundation
import PresentationKit

/// "Good day for an easy run with Luna": a soft offer on a rest day with a good run window (ADR-0041 keeps the rest
/// hero; this is one secondary line). Skipping it costs nothing: no streak, no wording about missing a day.
public struct RunOffer: Hashable, Sendable {
    /// "Good day for an easy run with Luna". Without a dog: "Good day for an easy run".
    public let title: String
    /// The run/walk example, e.g. "2 km easy · walk 1 km · 1 km easy". `nil` when there is no progression to show.
    public let plan: String?
    /// Why this day suits a run, for the details.
    public let reason: String
    /// Why the example looks like this, for the details.
    public let explanation: String?
    /// "Not today? Thursday also works"; `nil` when no other window is left in the cycle.
    public let fallback: String?
    /// "Not today": hides the offer for the rest of the day.
    public let dismissTitle: String

    public var summary: String { [title, plan].compactMap { $0 }.joined(separator: " · ") }

    public var accessibilityLabel: String { [summary, fallback].compactMap { $0 }.joined(separator: ". ") }

    struct Facts {
        let windows: [RunWindow]
        let today: CalendarDay
        let routine: WalkingRoutine
        let companionSlots: RunCompanionSlots?
        let progression: RunWalkProgression.Result?
        let calendar: Calendar
        let format: Format
    }

    /// The offer for today, or `nil` when today is not a rest day with a good window.
    static func make(_ facts: Facts) -> RunOffer? {
        let usable = facts.windows.filter { $0.quality != .avoid }
        guard let window = usable.first(where: { $0.day == facts.today }) else { return nil }
        let style = Date.FormatStyle(
            locale: facts.format.locale, calendar: facts.calendar, timeZone: facts.calendar.timeZone
        )
        let future = usable.filter { $0.day > facts.today }
        let preferred = future.first { facts.companionSlots?.prefersDog(on: $0.day, calendar: facts.calendar) == true }
        let fallback = (preferred ?? future.first).map {
            let weekday = $0.day.startDate(in: facts.calendar).formatted(style.weekday(.wide))
            return L10n.format("Not today? {1} also works", weekday)
        }
        let progression = facts.progression.flatMap { $0.phase == .goalReached || $0.blocks.isEmpty ? nil : $0 }
        return RunOffer(
            title: title(facts),
            plan: progression.map { RunningOption.progressionLine($0.blocks, format: facts.format) },
            reason: reason(window.reason),
            explanation: progression.map { RunningOption.progressionExplanation($0, format: facts.format) },
            fallback: fallback, dismissTitle: L10n.text("Not today")
        )
    }

    private static func title(_ facts: Facts) -> String {
        let routine = facts.routine
        guard routine.hasDog else { return L10n.text("Good day for an easy run") }
        if let slots = facts.companionSlots, slots.hasLearnedSlots,
           !slots.prefersDog(on: facts.today, calendar: facts.calendar) {
            return L10n.text("Good day for an easy run")
        }
        let name = routine.dogName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? L10n.text("Good day for an easy run with your dog")
            : L10n.format("Good day for an easy run with {1}", name)
    }

    private static func reason(_ reason: RunWindow.Reason) -> String {
        switch reason {
        case .awayFromLowerBody:
            L10n.text("No leg-heavy workout the day before or after, so your legs are fresh.")
        case .beforeHeavyLower:
            L10n.text("A leg-heavy workout follows tomorrow, so keep this one short and easy.")
        case .afterModerateLower:
            L10n.text("Your last workout worked your legs a little, so keep this one easy.")
        case .afterHeavyLower:
            L10n.text("Your legs are still recovering from a heavy workout.")
        }
    }
}
