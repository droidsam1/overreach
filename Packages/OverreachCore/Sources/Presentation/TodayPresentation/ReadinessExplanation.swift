import Domain
import Foundation
import PresentationKit

public struct ReadinessTrainingContext: Hashable, Sendable {
    public let heading: String
    public let workouts: [String]
}

/// Copy for the signals and observations already available to Today. This does not evaluate training readiness.
struct ReadinessExplanation {
    let readiness: Readiness
    let today: DailyMetrics?
    let week: [DailyMetrics]
    let training: [RecentTrainingDay]
    let calendar: Calendar
    let format: Format

    private var hasLowHRV: Bool {
        readiness.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } }
    }

    var summary: String? {
        guard hasLowHRV else { return nil }
        let hasElevatedPulse = readiness.reasons.contains {
            if case .restingHeartRateElevated = $0 { true } else { false }
        }
        return hasElevatedPulse
            ? L10n.text("Your HRV is trending below your usual range and your resting heart rate is higher than usual.")
            : L10n.text("Your HRV is trending below your usual range.")
    }

    var context: [String] {
        guard hasLowHRV, let coverage = readiness.hrvCoverage else { return [] }
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let latest = coverage.latestDay.startDate(in: calendar).formatted(style.day().month(.abbreviated))
        let baseline = L10n.format(
            "Your usual range uses {1} comparable readings from the previous {2} days. The latest reading was on {3}.",
            String(coverage.baselineReadings), String(coverage.baselineDays), latest
        )
        let sleep: String
        if let seconds = today?.sleepSeconds, seconds.isFinite, seconds > 0 {
            sleep = L10n.format("Sleep last night was {1} h.", format.number(seconds / 3_600, maxFractionDigits: 1))
        } else {
            sleep = L10n.text("Sleep data for last night is unavailable.")
        }
        return [
            L10n.text("HRV measures how much the time between heartbeats varies. "
                + "A sustained drop can inform training effort. Its cause is uncertain."),
            baseline, pulseContext, sleep,
        ]
    }

    private var pulseContext: String {
        guard let pulse = today?.restingHeartRate, pulse.isFinite, pulse > 0 else {
            return L10n.text("Resting heart rate is unavailable for today.")
        }
        let recent = week.compactMap(\.restingHeartRate).filter { $0.isFinite && $0 > 0 }
        let current = format.number(pulse, maxFractionDigits: 0)
        guard recent.count > 1 else { return L10n.format("Resting heart rate today is {1} bpm.", current) }
        let average = recent.reduce(0, +) / Double(recent.count)
        return L10n.format(
            "Resting heart rate today is {1} bpm. The average over {2} measured days in the last week is {3} bpm.",
            current, String(recent.count), format.number(average, maxFractionDigits: 0)
        )
    }

    var trainingContext: ReadinessTrainingContext? {
        guard hasLowHRV, let coverage = readiness.hrvCoverage else { return nil }
        let previousDay = coverage.latestDay.adding(days: -1, calendar: calendar)
        guard let day = training.first(where: { $0.id == previousDay }), !day.workouts.isEmpty else { return nil }
        return ReadinessTrainingContext(
            heading: L10n.format("Workouts recorded on {1}, the day before your latest comparable HRV reading.", day.date),
            workouts: day.workouts
        )
    }
}
