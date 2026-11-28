import PresentationKit

/// One alternative to the hero on the Options screen: a title, one line saying what it is and one verb. The
/// details open inside the card on the verb, not behind another level (ADR-0041).
public struct TodayOptionCard: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case run, lift, compareLift }

    public let kind: Kind
    public let title: String
    public let summary: String
    public let verb: String

    public var id: Kind { kind }

    static func run(_ option: RunningOption) -> TodayOptionCard {
        TodayOptionCard(
            kind: .run, title: L10n.text("I want to run today"), summary: option.advice,
            verb: L10n.text("Show the run")
        )
    }

    static var lift: TodayOptionCard {
        TodayOptionCard(
            kind: .lift, title: L10n.text("I want to lift today"),
            summary: L10n.text("A lighter session than usual, with your exercises and loads."),
            verb: L10n.text("Show the session")
        )
    }

    static var compareLift: TodayOptionCard {
        TodayOptionCard(
            kind: .compareLift, title: L10n.text("Compare with an easy strength option"),
            summary: L10n.text("Today's session with fewer sets and less load."),
            verb: L10n.text("Show the session")
        )
    }
}
