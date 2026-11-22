import Analytics
import Domain
import TrainingServices

extension ContextPack {
    /// Rule identifiers let clients interpret the decision independently of the app's display language.
    public struct Today: Codable, Hashable, Sendable {
        public var readiness: String
        public var reasons: [String]
        public var deload: TodayDeload
        /// Training already done on `period.to`'s day, so a reply does not propose a second session on top of it.
        public var training: TodayTraining?

        public init(_ assessment: DailyAssessment, training: DayTraining? = nil) {
            self.training = training.map(TodayTraining.init)
            readiness = assessment.readiness.level.rawValue
            reasons = assessment.readiness.reasons.compactMap(Self.reasonName)
            switch assessment.deload {
            case .inProgress:
                deload = TodayDeload(state: "inProgress")
            case .confirmBreak:
                deload = TodayDeload(state: "confirmBreak")
            case let .proposed(proposal, _, _):
                deload = TodayDeload(state: "proposed", signals: proposal.signals.compactMap(Self.signalName))
            case nil:
                deload = TodayDeload(state: "none")
            }
        }

        // These identifiers are a format contract. Keep the mapping explicit.
        // swiftlint:disable:next cyclomatic_complexity
        private static func reasonName(_ reason: ReadinessReason) -> String? {
            switch reason {
            case .markedSick: "markedSick"
            case .hrvBelowBaseline: "hrvBelowBaseline"
            case .hrvMayReflectCycle: "hrvMayReflectCycle"
            case .restingHeartRateElevated: "restingHeartRateElevated"
            case .phaseBaseline: "phaseBaseline"
            case .possibleLutealShift: "possibleLutealShift"
            case .shortSleep: "shortSleep"
            case .lowEnergy: "lowEnergy"
            case .highSoreness: "highSoreness"
            case .missingData: "missingData"
            default: nil
            }
        }

        /// Reported stress is private check-in context and stays out of what is shared.
        private static func signalName(_ signal: DeloadSignal) -> String? {
            switch signal {
            case .liftsStalled: "liftsStalled"
            case .rpeCreep: "rpeCreep"
            case .performanceDrop: "performanceDrop"
            case .weeksSinceDeload: "weeksSinceDeload"
            case .noDeloadInHistory: "noDeloadInHistory"
            case .weeklyLoadSpike: "weeklyLoadSpike"
            default: recoverySignalName(signal)
            }
        }

        private static func recoverySignalName(_ signal: DeloadSignal) -> String? {
            switch signal {
            case .hrvSuppressed: "hrvTrendBelowBaseline"
            case .restingHeartRateElevated: "restingHeartRateElevated"
            case .shortSleep: "shortSleep"
            case .poorWellbeing: "poorWellbeing"
            default: nil
            }
        }
    }

    /// `strength` and `run` say whether one was completed today. `lowerBody` is `none`, `today` or `yesterdayHeavy`.
    public struct TodayTraining: Codable, Hashable, Sendable {
        public var strength: Bool
        public var run: Bool
        public var lowerBody: String

        init(_ training: DayTraining) {
            strength = training.hasStrength
            run = training.hasRun
            lowerBody = switch training.lowerBody {
            case .none: "none"
            case .today: "today"
            case .yesterdayHeavy: "yesterdayHeavy"
            }
        }
    }

    public struct TodayDeload: Codable, Hashable, Sendable {
        public var state: String
        public var signals: [String]?
    }
}
