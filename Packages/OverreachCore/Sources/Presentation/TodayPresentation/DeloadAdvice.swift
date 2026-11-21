import Analytics
import Domain
import Foundation
import PresentationKit
import TrainingServices

/// One reason behind a deload proposal, with the strength of its evidence.
public struct DeloadReasonLine: Hashable, Sendable {
    public let text: String
    public let evidence: String
}

/// What Today shows about deloads: a proposal with its reasons, or the deload week in progress.
public struct DeloadAdvice: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Training and recovery suggest a deload week now.
        case proposed(reasons: [DeloadReasonLine])
        /// An accepted deload week, until `lastDay`.
        case inProgress(lastDay: Date)
        /// A deload would be proposed, but a recent break the athlete has not confirmed may already have been one.
        case confirmBreak(DetectedBreak)
    }

    /// A period of no or much lighter training that only the athlete can confirm (`unplanned-deload`).
    public struct DetectedBreak: Hashable, Sendable {
        public let start: CalendarDay
        public let end: CalendarDay
        public let reason: DeloadReason
        public let discipline: TrainingDiscipline?
        /// "No training logged from Mon 3 Nov to Tue 11 Nov."
        public let text: String
    }

    public let state: State
    /// "Same exercises, half the working sets, about 10 % less load, RPE 7 at most."
    public let planText: String

    static func make(
        _ assessment: DeloadAssessment, exercises: [Exercise], plan: DeloadPlan = .standard,
        calendar: Calendar, format: Format
    ) -> DeloadAdvice {
        let planText = L10n.format(
            "Same exercises, {1} of the working sets, about {2} less load, RPE {3} at most.",
            plan.setMultiplier == 0.5 ? L10n.text("half") : format.number(plan.setMultiplier * 100) + " %",
            format.number((1 - plan.loadMultiplier) * 100, maxFractionDigits: 0) + " %",
            format.number(plan.maximumRPE)
        )
        switch assessment {
        case let .inProgress(lastDay):
            return DeloadAdvice(state: .inProgress(lastDay: lastDay.startDate(in: calendar)), planText: planText)
        case let .confirmBreak(pending):
            let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
            let start = pending.start.startDate(in: calendar).formatted(style)
            let end = pending.end.startDate(in: calendar).formatted(style)
            let text = pending.reason == .noTraining
                ? L10n.format("No training logged from {1} to {2}.", start, end)
                : L10n.format("Much lighter training than usual from {1} to {2}.", start, end)
            return DeloadAdvice(
                state: .confirmBreak(DetectedBreak(start: pending.start, end: pending.end, reason: pending.reason,
                                                   discipline: pending.discipline, text: text)),
                planText: planText
            )
        case let .proposed(proposal, walkingIncluded):
            let namesByID = Exercise.displayNames(exercises)
            let names = proposal.stalledExerciseIDs.compactMap { namesByID[$0] }.sorted()
            let reasons = proposal.signals.map { signal in
                let summary = text(for: signal, format: format, walkingIncluded: walkingIncluded)
                if case .liftsStalled = signal, !names.isEmpty {
                    return DeloadReasonLine(
                        text: L10n.format("{1} The stalled exercises are {2}.", summary, names.joined(separator: ", ")),
                        evidence: signal.evidence.level.displayName
                    )
                }
                return DeloadReasonLine(text: summary, evidence: signal.evidence.level.displayName)
            }
            return DeloadAdvice(state: .proposed(reasons: reasons), planText: planText)
        }
    }

    static func text(for signal: DeloadSignal, format: Format, walkingIncluded: Bool = false) -> String {
        switch signal {
        case let .liftsStalled(count, mainLifts):
            if mainLifts {
                L10n.format("{1} main lifts have stalled.", count)
            } else {
                L10n.format("{1} lifts you train now have stalled.", count)
            }
        case let .performanceDrop(lifts):
            L10n.format("Estimated maxes dropped on {1} lifts this month.", lifts)
        case let .rpeCreep(lifts):
            L10n.format("The same weights feel harder on {1} lifts (RPE up).", lifts)
        case let .weeksSinceDeload(weeks):
            L10n.format("{1} weeks since your last deload.", weeks)
        case let .noDeloadInHistory(weeks):
            L10n.format("No deload or break in the {1} weeks of training logged.", weeks)
        case let .weeklyLoadSpike(ratio) where walkingIncluded:
            L10n.format("Strength and extra walking load reached {1}× your usual week.",
                        format.number(ratio, maxFractionDigits: 1))
        case let .weeklyLoadSpike(ratio):
            L10n.format("Training load rose fast this week ({1}× your usual).", format.number(ratio, maxFractionDigits: 1))
        case let .hrvSuppressed(days):
            L10n.format("Your 7-day HRV average was below your usual range on {1} of the last 7 days.", days)
        case let .restingHeartRateElevated(days):
            L10n.format("Resting HR above your usual on {1} of the last 7 days.", days)
        case let .shortSleep(nights):
            L10n.format("Less than 6 h of sleep on {1} of the last 7 nights.", nights)
        case let .poorWellbeing(checkIns):
            L10n.format("Low energy or sore in {1} check-ins this week.", checkIns)
        }
    }
}
