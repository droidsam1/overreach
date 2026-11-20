import Analytics
import Domain
import Foundation
import PresentationKit

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
    }

    public let state: State
    /// "Same exercises, half the working sets, about 10 % less load, RPE 7 at most."
    public let planText: String

    /// - Parameters:
    ///   - sessions: logged sessions (a year is enough for stalls and drops).
    ///   - history: merged daily metrics covering the readiness baseline (60 days before the last 7).
    ///   - checkIns: check-ins of the last 7 days.
    public static func make(
        today: CalendarDay, now: Date, sessions: [StrengthSession], exercises: [Exercise],
        settings: [UUID: ProgressionSettings], profile: AthleteProfile, history: [DailyMetrics], checkIns: [CheckIn],
        runs: [RunActivity] = [], runReadFailed: Bool = false, routines: [Routine] = [],
        recordings: [RecordedStrengthActivity] = [],
        readinessSettings: ReadinessRules.Settings = ReadinessRules.Settings(),
        advisorSettings: DeloadAdvisor.Settings = DeloadAdvisor.Settings(),
        calendar: Calendar = .current, format: Format = Format()
    ) -> DeloadAdvice? {
        let plan = advisorSettings.plan
        let planText = L10n.format(
            "Same exercises, {1} of the working sets, about {2} less load, RPE {3} at most.",
            plan.setMultiplier == 0.5 ? L10n.text("half") : format.number(plan.setMultiplier * 100) + " %",
            format.number((1 - plan.loadMultiplier) * 100, maxFractionDigits: 0) + " %",
            format.number(plan.maximumRPE)
        )
        if let current = profile.deloads.last, current.contains(today, calendar: calendar) {
            let lastDay = current.start.adding(days: max(1, current.days) - 1, calendar: calendar)
            return DeloadAdvice(state: .inProgress(lastDay: lastDay.startDate(in: calendar)), planText: planText)
        }
        if let postponed = profile.deloadPostponedUntil, today <= postponed { return nil }

        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let used = Set(sessions.flatMap { $0.entries.map(\.exerciseID) })
        let lifts = used.compactMap { id -> DeloadAdvisor.Lift? in
            guard let exercise = byID[id] else { return nil }
            let history = ExerciseExposure.history(of: id, in: sessions)
            guard !history.isEmpty else { return nil }
            return DeloadAdvisor.Lift(history: history, settings: settings[id] ?? ProgressionSettings(for: exercise))
        }
        let recovery = RecoveryTrend.assess(
            today: today, history: history, checkIns: checkIns, settings: readinessSettings, calendar: calendar
        )
        let detected = DeloadDetection.periods(
            sessions: sessions, runs: runs, profile: profile, routines: routines, exercises: byID,
            settings: settings, runReadFailed: runReadFailed, recordings: recordings, today: today, calendar: calendar
        )
        let lastDeload = profile.deloads.last.map { $0.start.startDate(in: calendar) }
        guard let proposal = DeloadAdvisor.proposal(
            lifts: lifts, lastDeload: lastDeload, recovery: recovery, now: now, settings: advisorSettings,
            detectedDeloads: detected, calendar: calendar
        ) else { return nil }
        let reasons = proposal.signals.map {
            DeloadReasonLine(text: text(for: $0, format: format), evidence: $0.evidence.level.displayName)
        }
        return DeloadAdvice(state: .proposed(reasons: reasons), planText: planText)
    }

    static func text(for signal: DeloadSignal, format: Format) -> String {
        switch signal {
        case let .liftsStalled(count):
            L10n.format("{1} main lifts have stalled.", count)
        case let .performanceDrop(lifts):
            L10n.format("Estimated maxes dropped on {1} lifts this month.", lifts)
        case let .rpeCreep(lifts):
            L10n.format("The same weights feel harder on {1} lifts (RPE up).", lifts)
        case let .weeksSinceDeload(weeks):
            L10n.format("{1} weeks since your last deload.", weeks)
        case let .weeklyLoadSpike(ratio):
            L10n.format("Training load rose fast this week ({1}× your usual).", format.number(ratio, maxFractionDigits: 1))
        case let .hrvSuppressed(days):
            L10n.format("HRV below your usual range on {1} of the last 7 days.", days)
        case let .restingHeartRateElevated(days):
            L10n.format("Resting HR above your usual on {1} of the last 7 days.", days)
        case let .shortSleep(nights):
            L10n.format("Less than 6 h of sleep on {1} of the last 7 nights.", nights)
        case let .poorWellbeing(checkIns):
            L10n.format("Low energy or sore in {1} check-ins this week.", checkIns)
        }
    }
}
