import Domain
import Foundation

/// The sentence for each reason of the recovery light. Today's "Why" and the plan follow-up use it, so both name a
/// signal the same way (ADR-0035).
public enum ReadinessReasonText {
    public static func text(for reason: ReadinessReason, readiness: Readiness, format: Format) -> String {
        switch reason {
        case .markedSick, .symptomsLimitTraining, .exerciseWarningSigns, .runningPainLimitsTraining,
             .unusualFatigue, .unusualStress, .lowEnergy, .highSoreness, .missingData:
            reported(reason)
        case .hrvBelowBaseline, .hrvMayReflectCycle, .phaseBaseline, .possibleLutealShift,
             .restingHeartRateElevated, .shortSleep:
            measured(reason, readiness: readiness, format: format)
        }
    }

    /// Reported in the check-in, or about the readings themselves.
    private static func reported(_ reason: ReadinessReason) -> String {
        switch reason {
        case .markedSick:
            L10n.text("Marked as sick in today's check-in. Rest until the symptoms ease.")
        case .symptomsLimitTraining:
            L10n.text("You reported symptoms that make you feel too unwell to train.")
        case .exerciseWarningSigns:
            L10n.text("Symptoms to discuss with a clinician")
        case .runningPainLimitsTraining:
            L10n.text("Running pain worsened or affected your stride")
        case .unusualFatigue:
            L10n.text("More fatigue than usual")
        case .unusualStress:
            L10n.text("More stress than usual")
        case .lowEnergy(let score):
            L10n.format("Low energy in today's check-in ({1}/5).", String(score))
        case .highSoreness(let score):
            L10n.format("Sore muscles in today's check-in ({1}/3).", String(score))
        default:
            L10n.text(
                "It needs about two weeks of HRV or resting HR from Apple Health, last night's sleep or a check-in."
            )
        }
    }

    private static func measured(_ reason: ReadinessReason, readiness: Readiness, format: Format) -> String {
        switch reason {
        case .hrvBelowBaseline(let nights):
            if let coverage = readiness.hrvCoverage, let metric = coverage.metric {
                L10n.format(
                    "HRV ({1}) below your usual range ({2} of {3} comparable readings low in the last {4} days).",
                    metric.seriesLabel, String(nights), String(coverage.recentReadings), String(coverage.recentDays)
                )
            } else {
                L10n.text("HRV below your usual range.")
            }
        case .hrvMayReflectCycle:
            L10n.text(
                "HRV is normally lower in the second half of the menstrual cycle, "
                    + "so this alone does not make the light red."
            )
        case .phaseBaseline(.follicular, let cycles):
            L10n.format("Compared with your follicular days in the last {1} cycles.", cycles)
        case .phaseBaseline(.luteal, let cycles):
            L10n.format("Compared with your luteal days in the last {1} cycles.", cycles)
        case .possibleLutealShift:
            L10n.text("Resting HR often rises a few beats before a period; the threshold allows for it.")
        case .restingHeartRateElevated(let bpm):
            L10n.format("Resting HR {1} bpm above your usual.", format.number(bpm, maxFractionDigits: 0))
        case .shortSleep(let hours):
            L10n.format("Short sleep: {1} h.", format.number(hours, maxFractionDigits: 1))
        default:
            ""  // `text(for:)` sends only the reasons above here
        }
    }
}
