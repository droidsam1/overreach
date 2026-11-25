import Domain
import Foundation
import PresentationKit

public struct HistoryWalk: Identifiable, Sendable {
    let walk: WalkBout
    let sources: [DataSourceKind]
    public let title = L10n.text("Walking")
    public let detail: String
    public let distance: String?

    public var startedAt: Date { walk.start }
    public var durationSeconds: TimeInterval { walk.durationSeconds }

    public var id: WalkKey { WalkKey(walk) }
    public var sourceText: String { sources.map(\.displayName).joined(separator: " · ") }

    init(_ walk: WalkBout, sources: [DataSourceKind], calendar: Calendar, format: Format) {
        self.walk = walk
        self.sources = sources
        distance = walk.distanceMeters.map { format.number($0 / 1_000, maxFractionDigits: 2) + " km" }
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let when = walk.start.formatted(style.day().month().year().hour().minute())
        let minutes = format.number((walk.durationSeconds / 60).rounded(), maxFractionDigits: 0)
        detail = L10n.format("Walk on {1}, {2} min", when, minutes)
    }
}

public struct HistoryWalkCompanion: Sendable {
    public let question: String
    public let answer: String?
    public let showsSuggestion: Bool
}
