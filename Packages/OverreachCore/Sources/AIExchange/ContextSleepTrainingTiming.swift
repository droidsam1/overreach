import Analytics
import TrainingServices

extension ContextPack {
    /// Aggregate observations for the recent window used by Recovery & Progress.
    public struct SleepTrainingTimingSummary: Codable, Hashable, Sendable {
        public let windowDays: Int
        public let nights: Int
        public let sessions: Int
        public let usualBedtimeMinutesAfterMidnight: Double?
        public let usualWakeMinutesAfterMidnight: Double?
        public let usualTrainingStartMinutesAfterMidnight: Double?
        public let bedtimeSpreadMinutes: Double?
        public let wakeSpreadMinutes: Double?
        public let midpointSpreadMinutes: Double?
        public let trainingSpreadMinutes: Double?
        public let regularityIndex: Double?
        public let weekendShiftMinutes: Double?
        public let hardSessions: Int
        public let hardSessionsNearBed: Int?
        public let insights: [TimingInsight]

        public init?(_ report: CircadianTiming.Report) {
            guard report.usualBedtime != nil || report.usualWake != nil || report.usualTrainingStart != nil
                || !report.insights.isEmpty else { return nil }
            windowDays = SleepTrainingTiming.windowDays
            nights = report.nights
            sessions = report.sessions
            usualBedtimeMinutesAfterMidnight = report.usualBedtime
            usualWakeMinutesAfterMidnight = report.usualWake
            usualTrainingStartMinutesAfterMidnight = report.usualTrainingStart
            bedtimeSpreadMinutes = report.bedtimeSpread
            wakeSpreadMinutes = report.wakeSpread
            midpointSpreadMinutes = report.midpointSpread
            trainingSpreadMinutes = report.trainingSpread
            regularityIndex = report.regularityIndex
            weekendShiftMinutes = report.weekendShift
            hardSessions = report.hardSessions
            hardSessionsNearBed = report.usualBedtime.map { _ in report.hardSessionsNearBed }
            insights = report.insights.map(TimingInsight.init)
        }
    }

    public enum TimingInsightKind: String, Codable, Sendable {
        case irregularSleep, socialJetlag, variableTrainingTime, hardSessionsNearBed
    }

    public struct TimingInsight: Codable, Hashable, Sendable {
        public let kind: TimingInsightKind
        public let evidenceKey: String
        public let evidenceLevel: String

        init(_ insight: CircadianTiming.Insight) {
            kind = switch insight {
            case .irregularSleep: .irregularSleep
            case .socialJetlag: .socialJetlag
            case .variableTrainingTime: .variableTrainingTime
            case .hardSessionsNearBed: .hardSessionsNearBed
            }
            evidenceKey = insight.evidence.key
            evidenceLevel = insight.evidence.level.rawValue
        }
    }
}
