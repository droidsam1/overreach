import Domain
import Foundation
import PresentationKit

/// Asks about a completed recorded run, independently of the walking routine's usual times.
public struct DogRunQuestion: Hashable, Sendable {
    let run: RunDeduplication.CombinedRun
    var key: DogRunAnswers.Key { .init(run.activity) }
    public let text: String
    public let detail: String

    @MainActor
    static func next(
        runs: [RunDeduplication.CombinedRun], answers: DogRunAnswers, routine: WalkingRoutine, now: Date,
        in context: DogWalkQuestion.Context
    ) -> Self? {
        guard routine.hasDog else { return nil }
        let earliest = now.addingTimeInterval(-48 * 3_600)
        guard let run = runs.last(where: { entry in
            let activity = entry.activity
            guard activity.durationSeconds.isFinite, activity.durationSeconds > 0 else { return false }
            let end = activity.startedAt.addingTimeInterval(activity.durationSeconds)
            return end >= earliest && end <= now && answers.answer(for: .init(activity), linked: entry.match) == nil
        }) else { return nil }

        let (calendar, format) = (context.calendar, context.format)
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let when = run.activity.startedAt.formatted(style.weekday(.wide).hour().minute())
        let minutes = format.number((run.activity.durationSeconds / 60).rounded(), maxFractionDigits: 0)
        return Self(run: run, text: DogWalkAnswers.question(for: routine),
                    detail: L10n.format("Run on {1}, {2} min", when, minutes))
    }
}
