import Analytics
import Foundation

/// The recorded context shown alongside the same recovery question in Today and Plan.
public struct DeloadQuestionDetails: Hashable, Sendable {
    public let dates: ClosedRange<Date>
    public let strength: String?
    public let running: String?
    public let reason: String

    public init(period: DetectedDeload, calendar: Calendar, format: Format = .init()) {
        dates = period.start.startDate(in: calendar)...period.end.startDate(in: calendar)
        if let activity = period.recordedActivity {
            let strengthCount = format.number(Double(activity.strengthSessions), maxFractionDigits: 0)
            if let ratio = activity.relativeSets {
                let percent = ratio.formatted(.percent.precision(.fractionLength(0)).locale(format.locale))
                strength = L10n.format(
                    "Strength sessions: {1}. About {2} of your usual weekly working sets.", strengthCount, percent
                )
            } else {
                strength = L10n.format("Strength sessions: {1}.", strengthCount)
            }
            let runs = L10n.format("Runs recorded: {1}.", format.number(Double(activity.runs), maxFractionDigits: 0))
            running = activity.hasIncompleteRunData
                ? L10n.format("{1} Running data may be incomplete.", runs)
                : runs
        } else {
            strength = nil
            running = nil
        }
        reason = period.discipline == .running
            ? L10n.text("Your answer updates your running recovery history.")
            : L10n.text("Your answer helps set when the next deload is due.")
    }
}
