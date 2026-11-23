import Analytics
import Domain
import Foundation
import PresentationKit

public struct RunningOption: Hashable, Sendable {
    public let goal: String
    public let plan: String?
    public let advice: String
    public let context: String?
    public let evidence: String?
    public let source: URL?
    public let explanation: String?
    public let adjustment: Adjustment?
    public let isOptional: Bool
    let offersEasyRun: Bool
    let suggestedMinutes: Int?

    public struct Adjustment: Hashable, Sendable {
        public let original: PlannedRun
        public let minutes: Int
        public let applyTitle: String
        public let keepTitle: String
        public let moveDay: CalendarDay?
        public let moveTitle: String?
        public var runID: UUID { original.id }
    }

    private init(
        goal: String, advice: String, plan: String? = nil, context: String? = nil, evidence: EvidenceReference? = nil,
        source: String? = nil, explanation: String? = nil, adjustment: Adjustment? = nil,
        isOptional: Bool = false, offersEasyRun: Bool = false, suggestedMinutes: Int? = nil
    ) {
        self.goal = goal
        self.plan = plan
        self.advice = advice
        self.context = context
        self.evidence = evidence?.level.displayName
        self.source = source.flatMap { URL(string: $0) }
        self.explanation = explanation
        self.adjustment = adjustment
        self.isOptional = isOptional
        self.offersEasyRun = offersEasyRun
        self.suggestedMinutes = suggestedMinutes
    }

    init(
        goal trainingGoal: TrainingGoal?, decision: EasyRunAdvisor.Decision, hasRunToday: Bool,
        lowerBody: LowerBodyLoad.Level = .none, progression: RunWalkProgression.Result? = nil,
        calendar: Calendar, format: Format
    ) {
        let goal = trainingGoal?.running
        let title = goal?.displayName(format: format) ?? L10n.text("Running")
        switch decision {
        case .plannedRest:
            self.init(goal: title, advice: L10n.text("Keep your planned running rest day."))
        case .raceToday:
            self.init(goal: title, advice: L10n.text("Your race is today. Follow the recovery advice above."))
        case .scheduledStrength:
            self.init(goal: title, advice: L10n.text("Keep your scheduled strength session as the priority."))
        case .familiarEffort:
            self.init(
                goal: title, advice: L10n.text("If you run today, keep it easy and at a conversational pace."),
                context: Self.painFreeContext(L10n.text("Choose a duration you are used to."), goal: goal),
                isOptional: true, offersEasyRun: true
            )
            self = Self.applying(progression, to: self, format: format)
        case .nearEvent:
            self.init(goal: title, advice: L10n.text(
                "Your race or target date is today or tomorrow. Leave the extra run for another day."
            ))
        case .multipleToday:
            self.init(goal: title, advice: L10n.text(
                "You have several runs planned today. Review them in Plan before adding or replacing a run."
            ))
        case .lowerBodyRecovery(let level):
            let reason = level == .today
                ? L10n.text("You trained your legs today. An extra run now adds load without a plan behind it.")
                : L10n.text(
                    "You trained your legs hard yesterday. An extra run now adds load without a plan behind it."
                )
            self.init(
                goal: title, advice: L10n.text("Leave the run for another day, or keep to a walk."),
                context: reason, evidence: LowerBodyLoad.evidence,
                explanation: L10n.text(
                    "Strength and endurance work together well over a week. Sessions close together can blunt "
                        + "explosive strength and make the second one harder. A heuristic, not a rule."
                )
            )
        case .returningFromBreak(let replacePlanned):
            self = Self.returningOption(
                title: title, goal: goal, replacePlanned: replacePlanned, hasRunToday: hasRunToday
            )
        case .example(let minutes, let next, let isToday, let recentRuns):
            let plan = next.map { Self.planText($0, isToday: isToday, calendar: calendar, format: format) }
            let reduction = isToday && (next?.purpose != .easy || next?.durationMinutes != minutes)
            let advice = Self.exampleAdvice(minutes: minutes, next: next, isToday: isToday, reduction: reduction)
            let basis = L10n.format("Duration based on {1} recent runs.", String(recentRuns))
            let anchor = lowerBody == .none ? basis
                : basis + " " + L10n.text("Kept short because you trained your legs close to this run.")
            self.init(
                goal: title, advice: advice, plan: plan, context: Self.painFreeContext(anchor, goal: goal),
                evidence: EasyRunAdvisor.evidence, source: "https://pubmed.ncbi.nlm.nih.gov/18277826/",
                explanation: L10n.text(
                    "A conversational pace keeps the effort easy. The duration is a coaching estimate."
                ), adjustment: Self.adjustment(plan: isToday ? next : nil, goal: trainingGoal, minutes: minutes,
                                               calendar: calendar, format: format),
                isOptional: !isToday, offersEasyRun: true, suggestedMinutes: minutes
            )
            if !isToday || next == nil {
                self = Self.applying(progression, to: self, format: format)
            }
        }
    }

    /// One line of distance blocks, for example "2 km easy · walk 0.5 km · 0.5 km easy". Longer sessions repeat the
    /// same pair: "3 × (1.2 km easy · walk 0.3 km) · 0.4 km easy".
    static func progressionLine(_ blocks: [RunWalkProgression.Block], format: Format) -> String {
        func text(_ block: RunWalkProgression.Block) -> String {
            let distance = format.number(Double(block.meters) / 1_000, maxFractionDigits: 2)
            return switch block {
            case .run: L10n.format("{1} km easy", distance)
            case .walk: L10n.format("walk {1} km", distance)
            }
        }
        guard blocks.count > 3 else { return blocks.map(text).joined(separator: " · ") }
        let pair = Array(blocks.prefix(2))
        var repeats = 0
        while blocks.count >= (repeats + 1) * 2,
              Array(blocks[(repeats * 2)..<(repeats * 2 + 2)]) == pair { repeats += 1 }
        let tail = blocks.dropFirst(repeats * 2).map(text)
        let head = "\(repeats) × (" + pair.map(text).joined(separator: " · ") + ")"
        return ([head] + tail).joined(separator: " · ")
    }

    /// Replaces the single duration with the run/walk example. The level 2 text says why this step.
    private static func applying(_ progression: RunWalkProgression.Result?, to option: Self, format: Format) -> Self {
        guard let progression, progression.phase != .goalReached, !progression.blocks.isEmpty else { return option }
        let line = progressionLine(progression.blocks, format: format)
        return Self(
            goal: option.goal, advice: L10n.format("If you want to run today, try {1}.", line), plan: option.plan,
            context: option.context, evidence: RunWalkProgression.evidence,
            source: "https://doi.org/10.1136/bjsports-2024-109380",
            explanation: progressionExplanation(progression, format: format), adjustment: option.adjustment,
            isOptional: option.isOptional,
            offersEasyRun: option.offersEasyRun, suggestedMinutes: nil
        )
    }

    /// Why this step, the 10% cap and the reminder that distances, not pace, set the effort.
    static func progressionExplanation(_ progression: RunWalkProgression.Result, format: Format) -> String {
        let settings = RunWalkProgression.Settings()
        let reason = switch progression.phase {
        case .start: L10n.text("No recent run to build on, so this starts gently.")
        case .progress: L10n.text("Your last run had no reported pain, so this adds one small step.")
        case .hold(let afterGap):
            if afterGap {
                L10n.text("It has been a while since your last run, so this repeats a pain-free distance.")
            } else {
                L10n.text("You reported pain after your last run, so this repeats a pain-free distance.")
            }
        case .stepBack: L10n.text("You reported pain after two runs in a row, so this goes back one step.")
        case .goalReached: ""
        }
        return [reason, L10n.format(
            "The whole session stays within {1} of your longest run in the last {2} days, walking included.",
            settings.sessionIncreaseFraction.formatted(.percent.locale(format.locale)), String(settings.historyDays)
        ), L10n.text(
            "Distances, not pace, set the effort. Stop and walk if you notice pain. A coaching estimate."
        )].joined(separator: " ")
    }

    private static func exampleAdvice(minutes: Int, next: PlannedRun?, isToday: Bool, reduction: Bool) -> String {
        guard isToday else {
            return L10n.format("If you want to run today, try {1} min at a conversational pace.", String(minutes))
        }
        guard reduction else { return L10n.text("Keep today's planned easy run at a conversational pace.") }
        if next?.purpose == .easy {
            return L10n.format("Keep today's run easy. Try {1} min at a conversational pace.", String(minutes))
        }
        return L10n.format("Try {1} min at a conversational pace in place of the planned session.", String(minutes))
    }

    private static func returningOption(
        title: String, goal: RunningGoal?, replacePlanned: Bool, hasRunToday: Bool
    ) -> Self {
        let advice = replacePlanned
            ? L10n.text("Replace today's planned run with an easy run at a conversational pace.")
            : L10n.text("If you run today, keep it easy and at a conversational pace.")
        let text = L10n.text("You're returning from a running break.")
        return Self(
            goal: title, advice: advice, context: Self.painFreeContext(text, goal: goal),
            evidence: EasyRunAdvisor.returnEvidence, source: "https://pubmed.ncbi.nlm.nih.gov/33517866/",
            explanation: L10n.text(
                "Endurance can change during a break. Keeping the first runs easy is a coaching estimate."
            ), isOptional: !hasRunToday, offersEasyRun: true
        )
    }

    private static func adjustment(
        plan: PlannedRun?, goal: TrainingGoal?, minutes: Int, calendar: Calendar, format: Format
    ) -> Adjustment? {
        guard let plan, let goal, goal.running != nil, plan.purpose != .easy,
              plan.easingTo(minutes: minutes) != plan else { return nil }
        let moveDay = EasyRunAdvisor.rescheduleDay(for: plan, goal: goal, calendar: calendar)
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let moveTitle = moveDay.map {
            let date = $0.startDate(in: calendar).formatted(style.weekday(.wide).day().month(.abbreviated))
            return L10n.format("Review move to {1}", date)
        }
        return Adjustment(
            original: plan, minutes: minutes, applyTitle: L10n.format("Change to {1} min easy", String(minutes)),
            keepTitle: L10n.text("Keep the planned run"), moveDay: moveDay, moveTitle: moveTitle
        )
    }

    private static func planText(_ next: PlannedRun, isToday: Bool, calendar: Calendar, format: Format) -> String {
        let label = next.displayName(format: format)
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        let date = next.day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
        return isToday
            ? L10n.format("Today's running plan · {1}", label)
            : L10n.format("Next planned running day · {1} · {2}", date, label)
    }

    private static func painFreeContext(_ text: String, goal: RunningGoal?) -> String {
        goal?.aimsForPainFree == true
            ? text + " " + L10n.text("For your pain-free goal, stop if you notice pain.")
            : text
    }
}
