import Analytics
import Domain
import Foundation
import PresentationKit

/// The card's leading reason and the details that support the proposal.
public struct DeloadExplanation: Hashable, Sendable {
    public let summary: String
    public let trainingReasons: [String]
    public let recoveryReasons: [String]
    public let lastRest: String
    public let evidence: [DeloadEvidenceLine]
    public let readings: [Reading]
    /// Whether the athlete said they are under more stress than usual, which changes the week proposed.
    public let lifeStress: RecoveryTrend.LifeStress
    /// What the athlete said about stress, and what may help this week; empty unless they reported stress.
    public let stressContext: [String]

    static func make(
        _ proposal: DeloadProposal, exercises: [Exercise], walkingIncluded: Bool,
        lastRest: (text: String, kind: LastRecovery.Kind?), format: Format
    ) -> Self {
        let namesByID = Exercise.displayNames(exercises)
        let names = proposal.stalledExerciseIDs.compactMap { namesByID[$0] }.sorted()
        var trainingReasons: [String] = []
        var recoveryReasons: [String] = []
        var references = [ProgressionEvidence.deloadDesign]
        for signal in proposal.signals {
            let reason = DeloadAdvice.text(for: signal, format: format, walkingIncluded: walkingIncluded)
            switch signal {
            case .hrvSuppressed, .restingHeartRateElevated, .shortSleep, .poorWellbeing:
                recoveryReasons.append(reason)
            case .lifeStressReported:
                break
            case .liftsStalled where !names.isEmpty:
                trainingReasons.append(
                    L10n.format("{1} The stalled exercises are {2}.", reason, names.joined(separator: ", "))
                )
            case let .weeksSinceDeload(weeks) where lastRest.kind == .detectedBreak:
                trainingReasons.append(L10n.format("{1} weeks since your last strength rest period.", weeks))
            default:
                trainingReasons.append(reason)
            }
            if !references.contains(signal.evidence) {
                references.append(signal.evidence)
            }
        }
        let stressed = proposal.lifeStress == .reported
        return Self(
            summary: stressed ? stressSummary : summary(for: proposal.signals),
            trainingReasons: trainingReasons, recoveryReasons: recoveryReasons,
            lastRest: lastRest.text,
            evidence: references.compactMap(DeloadEvidenceLine.init),
            readings: FurtherReading.readings(for: references),
            lifeStress: proposal.lifeStress,
            stressContext: stressed ? [
                DeloadAdvice.text(for: .lifeStressReported, format: format),
                L10n.text("Stress can lower HRV and slow recovery, so some signs above may come from it."),
                L10n.text("Train on your usual days at a comfortable effort. A walk, an easy run or a light lift may help."),
                L10n.text("Leave sets to failure and personal-record attempts for when you feel steadier."),
                L10n.text("Protect your sleep: stress and short nights add up."),
            ] : []
        )
    }

    static var stressSummary: String {
        L10n.text(
            "Some lifts have stalled and you reported more stress than usual. A steadier week may suit you better."
        )
    }

    static func summary(for signals: [DeloadSignal]) -> String {
        let stalled = signals.contains { if case .liftsStalled = $0 { true } else { false } }
        let harder = signals.contains { if case .rpeCreep = $0 { true } else { false } }
        let dropped = signals.contains { if case .performanceDrop = $0 { true } else { false } }

        if dropped && harder {
            return L10n.text("Your estimated maxes have dropped and the same weights feel harder.")
        }
        if stalled && harder {
            return L10n.text("Some lifts have stopped progressing and the same weights feel harder.")
        }
        if dropped {
            return L10n.text("Your estimated maxes have dropped on several lifts.")
        }
        if harder {
            return L10n.text("The same weights feel harder on several lifts.")
        }
        if signals.contains(where: { if case .weeklyLoadSpike = $0 { true } else { false } }) {
            return L10n.text("Some lifts have stopped progressing and your training load rose sharply this week.")
        }
        return L10n.text("Some lifts have stopped progressing and recent recovery signs support a lighter week.")
    }

    static func restText(_ rest: LastRecovery?, calendar: Calendar, format: Format) -> String {
        guard let rest else { return L10n.text("No strength deload or rest period in your logged history.") }
        let style = Date.FormatStyle(
            date: .abbreviated, time: .omitted, locale: format.locale, calendar: calendar, timeZone: calendar.timeZone
        )
        let date = rest.lastDay.startDate(in: calendar).formatted(style)
        switch rest.kind {
        case .deloadWeek: return L10n.format("Your last deload week ended on {1}.", date)
        case .detectedBreak: return L10n.format("Your last strength rest period ended on {1}.", date)
        }
    }
}

/// One explanation per evidence key, even when several signals use it.
public struct DeloadEvidenceLine: Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let level: String

    init?(_ reference: EvidenceReference) {
        id = reference.key
        level = reference.level.displayName
        switch reference.key {
        case "deload-design":
            text = L10n.text("Coaches recommend shorter or easier strength sessions to manage fatigue.")
        case "rpe-creep":
            text = L10n.text("Overreach treats rising effort at the same weight and reps as a sign of fatigue.")
        case "deload-practice":
            text = L10n.text("Strength athletes report taking lighter weeks roughly every five to six weeks.")
        case "weekly-load-change":
            text = L10n.text("A sharp rise in weekly load is a rough clue that training has been more demanding.")
        case "deload-life-stress":
            text = L10n.text(
                "Stress outside training adds to the load your body recovers from and can lower HRV on its own."
            )
        case "deload-recovery-signals":
            text = L10n.text("Sleep, heart measurements and how you feel can add context to changes in your training.")
        default:
            return nil
        }
    }
}

public enum DeloadProposalText {
    public static var title: String { L10n.text("Deload week suggested") }
    public static var start: String { L10n.text("Start deload week") }
    public static func title(steadier: Bool) -> String {
        steadier ? L10n.text("Steadier week suggested") : title
    }

    public static func start(steadier: Bool) -> String {
        steadier ? L10n.text("Start steadier week") : start
    }

    public static func weekInProgress(steadier: Bool) -> String {
        steadier ? L10n.text("Steadier week") : L10n.text("Deload week")
    }
    public static var yourStress: String { L10n.text("Your stress") }
    public static var postpone: String { L10n.text("Not now") }
    public static var details: String { L10n.text("Why and what changes") }
    public static var whyNow: String { L10n.text("Why now") }
    public static var supportingRecovery: String { L10n.text("Supporting recovery signs") }
    public static var lastRest: String { L10n.text("Your last rest") }
    public static var history: String { L10n.text("Recovery history") }
    public static var whatChanges: String { L10n.text("What changes") }
    public static var session: String { L10n.text("See your deload session") }
    public static var evidence: String { L10n.text("Evidence") }
}
