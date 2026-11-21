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
    let training: [RecentTrainingDay]
    let calendar: Calendar
    let format: Format

    private var hasLowHRV: Bool {
        readiness.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } }
    }

    var observations: [ReadinessObservation] {
        guard !readiness.reasons.contains(where: \.advisesSkippingTraining) else { return [] }
        var observations: [ReadinessObservation] = []
        if readiness.hrvInput?.status == .compared {
            observations.append(.init(kind: .context, text: L10n.text(
                "HRV measures how much the time between heartbeats varies. "
                    + "A sustained drop can inform training effort. Its cause is uncertain."
            )))
        }
        if let pulse = readiness.input(.restingHeartRate) {
            observations.append(pulseObservation(pulse))
        }
        if let sleep = readiness.input(.sleep) {
            observations.append(sleepObservation(sleep))
        }
        return observations
    }

    private func pulseObservation(_ pulse: ReadinessInputAudit) -> ReadinessObservation {
        guard let value = pulse.value else {
            return .init(kind: .unavailable, text: L10n.text("Resting heart rate is unavailable for today."))
        }
        let current = format.number(value, maxFractionDigits: 0)
        if pulse.outcome == .within, let reference = pulse.reference?.value {
            return .init(kind: .context, text: L10n.format(
                "Resting heart rate today is within your usual range ({1} bpm, baseline average {2} bpm).",
                current, format.number(reference, maxFractionDigits: 0)
            ))
        }
        return .init(kind: .context, text: L10n.format("Resting heart rate today is {1} bpm.", current))
    }

    private func sleepObservation(_ sleep: ReadinessInputAudit) -> ReadinessObservation {
        guard let value = sleep.value else {
            return .init(kind: .unavailable, text: L10n.text("Sleep data for last night is unavailable."))
        }
        return .init(kind: .context, text: L10n.format(
            "Sleep last night was {1} h.", format.number(value, maxFractionDigits: 1)
        ))
    }

    var sources: [ReadinessSourceDetail] {
        guard !readiness.reasons.contains(where: \.advisesSkippingTraining) else { return [] }
        return readiness.inputs.map { ReadinessSourceDetail(audit: $0, calendar: calendar, format: format) }
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
