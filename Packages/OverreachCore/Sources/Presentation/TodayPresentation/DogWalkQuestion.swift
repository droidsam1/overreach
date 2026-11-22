import Analytics
import Domain
import Foundation
import PresentationKit

/// "With Nanoq?" for the latest walk worth asking about (docs/design/companion-walks.md#suggest-and-confirm).
/// One tap answers it. It never blocks anything: an unanswered walk is an ordinary walk.
public struct DogWalkQuestion: Hashable, Sendable {
    /// Only walks this recent are asked about in Today. Older ones can still be tagged from History.
    static let recentHours: TimeInterval = 48

    public let walk: WalkBout
    /// "With Nanoq?" or "With your dog?" without a name.
    public let text: String
    /// When and how long, so the athlete knows which walk is meant.
    public let detail: String

    public var accessibilityLabel: String { "\(text) \(detail)" }

    struct Context {
        let calendar: Calendar
        let format: Format
    }

    static func next(
        activity: [DailyActivity], answers: [WalkCompanionAnswer], routine: WalkingRoutine, now: Date,
        in context: Context
    ) -> DogWalkQuestion? {
        let (calendar, format) = (context.calendar, context.format)
        guard routine.hasDog else { return nil }
        let since = now.addingTimeInterval(-recentHours * 3_600)
        // The whole history teaches the usual slots; only the latest unanswered recent walk is asked about.
        let walks = activity.flatMap(\.walks).filter { $0.start <= now }
        guard let walk = DogWalkSuggestion.walksToAsk(
            walks: walks, answers: answers, now: now, calendar: calendar
        ).last(where: { $0.start >= since }) else { return nil }

        let name = routine.dogName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = name.isEmpty ? L10n.text("With your dog?") : L10n.format("With {1}?", name)
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let when = walk.start.formatted(style.weekday(.wide).hour().minute())
        let minutes = format.number((walk.durationSeconds / 60).rounded(), maxFractionDigits: 0)
        return DogWalkQuestion(walk: walk, text: text, detail: L10n.format("Walk on {1}, {2} min", when, minutes))
    }
}
