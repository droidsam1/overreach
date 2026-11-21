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
    let nights: [DailyMetrics]
    let plausibleHRV: ClosedRange<Double>
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
        if let raceComparison {
            observations.append(.init(kind: .context, text: raceComparison))
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

    private var activities: [RecentTraining.Activity] {
        training.flatMap(\.activities).sorted { $0.startedAt < $1.startedAt }
    }

    private var dayStyle: Date.FormatStyle {
        Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.abbreviated)
    }

    private func night(_ day: CalendarDay) -> DailyMetrics? {
        nights.last { $0.day == day }
    }

    var trainingContext: ReadinessTrainingContext? {
        guard hasLowHRV, let coverage = readiness.hrvCoverage else { return nil }
        if let metric = coverage.metric, let reading = night(coverage.latestDay)?.hrvReadingInterval(metric) {
            return trainingBefore(reading, day: coverage.latestDay)
        }
        // Without the reading's interval only calendar order is known: the previous day is before the night.
        let previousDay = coverage.latestDay.adding(days: -1, calendar: calendar)
        guard let day = training.first(where: { $0.id == previousDay }), !day.workouts.isEmpty else { return nil }
        return ReadinessTrainingContext(
            heading: L10n.format("Workouts recorded on {1}, the day before your latest comparable HRV reading.", day.date),
            workouts: day.workouts
        )
    }

    /// Workouts that ended between the previous sleep and the sleep behind the reading. Overnight sessions and time
    /// zone changes follow the recorded timestamps, not the calendar day.
    private func trainingBefore(_ reading: ClosedRange<Date>, day: CalendarDay) -> ReadinessTrainingContext? {
        let previousNight = night(day.adding(days: -1, calendar: calendar))?.sleepInterval
        let previousWake = previousNight.flatMap { $0.upperBound < reading.lowerBound ? $0.upperBound : nil }
        let start = previousWake ?? reading.lowerBound.addingTimeInterval(-24 * 3_600)
        let workouts = activities.filter { $0.endedAt > start && $0.endedAt <= reading.lowerBound }
        guard !workouts.isEmpty else { return nil }
        let date = day.startDate(in: calendar).formatted(dayStyle)
        let heading = previousWake == nil
            ? L10n.format(
                "Workouts in the 24 hours before the night of your latest comparable HRV reading ({1}).", date
            )
            : L10n.format(
                "Workouts since your last sleep, before the night of your latest comparable HRV reading ({1}).", date
            )
        return ReadinessTrainingContext(heading: heading, workouts: workouts.map(\.text))
    }

    /// The most recent confirmed race this week next to the closest comparable readings before and after it. It
    /// shows the order of events; it does not say the race caused a change (ADR-0034).
    var raceComparison: String? {
        guard hasLowHRV, let coverage = readiness.hrvCoverage, let metric = coverage.metric,
              let window = coverage.window,
              let race = activities.last(where: \.isRace) else { return nil }
        let raceDay = CalendarDay(race.startedAt, calendar: calendar)
        let readings = nights.compactMap { night -> Reading? in
            guard night.hrvWindow(metric) == window, let value = night.hrv(metric),
                  plausibleHRV.contains(value) else { return nil }
            return Reading(day: night.day, value: value, interval: night.hrvReadingInterval(metric))
        }
        let before = readings.last { reading in
            if let interval = reading.interval { return interval.upperBound <= race.startedAt }
            // A night is attributed to the day it ends, so it precedes a race that day. Daytime readings may not.
            return window == .sleep ? reading.day <= raceDay : reading.day < raceDay
        }
        let after = readings.first { reading in
            if let interval = reading.interval { return interval.lowerBound >= race.endedAt }
            return reading.day > raceDay
        }
        let date = race.startedAt.formatted(dayStyle)
        let statistic = metric.rawValue.uppercased()
        switch (before.map(text), after.map(text)) {
        case let (before?, after?):
            return L10n.format("Confirmed race on {1}. Comparable HRV ({2}) before it: {3}. After it: {4}.",
                               date, statistic, before, after)
        case let (before?, nil):
            return L10n.format(
                "Confirmed race on {1}. Comparable HRV ({2}) before it: {3}. No comparable reading after it yet.",
                date, statistic, before
            )
        case let (nil, after?):
            return L10n.format("Confirmed race on {1}. No comparable HRV ({2}) reading before it. After it: {3}.",
                               date, statistic, after)
        case (nil, nil):
            return nil
        }
    }

    private struct Reading {
        let day: CalendarDay
        let value: Double
        let interval: ClosedRange<Date>?
    }

    private func text(_ reading: Reading) -> String {
        L10n.format("{1} ms on {2}", format.number(reading.value, maxFractionDigits: 0),
                    reading.day.startDate(in: calendar).formatted(dayStyle))
    }
}
