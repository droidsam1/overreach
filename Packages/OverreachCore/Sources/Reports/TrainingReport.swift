import Analytics
import Domain
import Foundation

/// A compact summary of one strength session for the report.
public struct SessionSummary: Hashable, Sendable {
    public var day: CalendarDay
    public var name: String
    public var tonnageKg: Double
    public var effectiveSets: [MuscleGroup: Double]
    public var rotationAdjustments: [RotationAdjustment.Outcome]

    public init(
        day: CalendarDay, name: String, tonnageKg: Double, effectiveSets: [MuscleGroup: Double],
        rotationAdjustments: [RotationAdjustment.Outcome] = []
    ) {
        self.day = day
        self.name = name
        self.tonnageKg = tonnageKg
        self.effectiveSets = effectiveSets
        self.rotationAdjustments = rotationAdjustments
    }
}

/// Everything the report contains. Built by the app from repositories and `Analytics`; rendered by
/// `MarkdownReportRenderer`. The same content will feed the in-app assistant (ADR-0006).
public struct TrainingReport: Sendable {
    public var generatedAt: Date
    /// Fixed notes about the athlete: goals, plan, injuries. Written by the user in Settings.
    public var athleteContext: String?
    public var today: DailyMetrics?
    public var readiness: Readiness?
    /// Daily metrics, any order; the renderer sorts them newest first.
    public var recentDays: [DailyMetrics]
    public var recentSessions: [SessionSummary]
    public var recentRuns: [RunActivity]
    public var checkIns: [CheckIn]
    public var question: String?
    /// Rendered balance suggestions from the same audit used in Trends.
    public var muscleBalance: [String]
    public var sleepTrainingTiming: CircadianTiming.Report?

    public init(
        generatedAt: Date,
        athleteContext: String? = nil,
        today: DailyMetrics? = nil,
        readiness: Readiness? = nil,
        recentDays: [DailyMetrics] = [],
        recentSessions: [SessionSummary] = [],
        recentRuns: [RunActivity] = [],
        checkIns: [CheckIn] = [],
        question: String? = nil,
        muscleBalance: [String] = [],
        sleepTrainingTiming: CircadianTiming.Report? = nil
    ) {
        self.generatedAt = generatedAt
        self.athleteContext = athleteContext
        self.today = today
        self.readiness = readiness
        self.recentDays = recentDays
        self.recentSessions = recentSessions
        self.recentRuns = recentRuns
        self.checkIns = checkIns
        self.question = question
        self.muscleBalance = muscleBalance
        self.sleepTrainingTiming = sleepTrainingTiming
    }
}
