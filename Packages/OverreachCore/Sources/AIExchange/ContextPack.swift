import Foundation

/// Training context exported for an AI assistant (ADR-0017, field reference in `docs/ai-exchange.md`): logged
/// sessions, exercise settings, health metrics and trends computed by the app, with no instructions.
///
/// These are the format's own types, not the domain's, so the format only changes on purpose. Adding an optional
/// field keeps `version`; renaming or removing a field, or changing its meaning or unit, raises it.
public struct ContextPack: Codable, Hashable, Sendable {
    public static let formatName = "overreach.context"
    public static let currentVersion = 1

    public var format = Self.formatName
    public var version = Self.currentVersion
    /// What the data is, for a reader that sees only the JSON (e.g. a shared file).
    public var about: String
    public var generatedAt: Date
    public var app: AppInfo
    public var units = Units()
    public var period: Period
    public var athlete: Athlete
    /// Names of every exercise available in the app, so suggestions can use them.
    public var catalog: [String]
    /// Exercises used in the period, in routines or with their own settings.
    public var exercises: [ExerciseInfo]
    public var routines: [RoutineInfo]
    /// Strength sessions in the period, oldest first.
    public var sessions: [Session]
    public var exerciseTrends: [ExerciseTrend]
    public var checkIns: [CheckInInfo]
    public var dailyMetrics: [Metrics]
    public var runs: [Run]
    /// Formats the app can import back. Optional, added after v1 shipped.
    public var imports: [ImportFormat]?

    public struct ImportFormat: Codable, Hashable, Sendable {
        public var format: String
        public var version: Int
        public var reference: String
        /// JSON Schema of the format. Optional, added after v1 shipped.
        public var schema: String?
    }

    public struct AppInfo: Codable, Hashable, Sendable {
        public var name: String
        public var version: String?
    }

    public struct Units: Codable, Hashable, Sendable {
        public var weight = "kg"
        public var distance = "m"
        public var duration = "s"
        public var heartRate = "bpm"
        public var hrv = "ms"
    }

    /// Calendar days, `YYYY-MM-DD`, both included.
    public struct Period: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
    }

    public struct Athlete: Codable, Hashable, Sendable {
        public var sex: String?
        public var birthYear: Int?
        public var bodyMassKg: Double?
        public var maxHeartRate: Double?
        public var restingHeartRate: Double?
        public var cycleTracking: String?
        public var goal: Goal?
        public var declaredBlocks: [Block]
    }

    public struct Goal: Codable, Hashable, Sendable {
        public var kind: String
        public var targetDate: String?
        public var priorityLifts: [String]
    }

    public struct Block: Codable, Hashable, Sendable {
        public var focus: String
        public var start: String
        public var plannedWeeks: Int?
        public var name: String?
        /// Routine names the block rotates through, in order (a training plan).
        public var routines: [String]?
        public var sessionsPerWeek: Int?
    }

    public struct ExerciseInfo: Codable, Hashable, Sendable {
        public var name: String
        public var equipment: String
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]?
        public var isCustom: Bool?
        /// The exercise's own progression settings; absent = the app's defaults.
        public var progression: Progression?
    }

    public struct Progression: Codable, Hashable, Sendable {
        public var focus: String?
        public var scheme: Scheme
        public var incrementKg: Double
        public var isMainLift: Bool
    }

    /// `type` is `doubleProgression` (minReps–maxReps), `linearLoad` (reps), `repCycle` (repBlocks) or
    /// `rpeBased` (reps).
    public struct Scheme: Codable, Hashable, Sendable {
        public var type: String
        public var sets: Int
        public var minReps: Int?
        public var maxReps: Int?
        public var reps: Int?
        public var repBlocks: [Int]?
        public var targetRPE: Double
    }

    public struct RoutineInfo: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var focus: String?
        public var exercises: [String]
        /// Sets and reps for exercises of this routine only.
        public var prescriptions: [Prescription]?
    }

    public struct Prescription: Codable, Hashable, Sendable {
        public var exercise: String
        public var scheme: Scheme
    }

    public struct Session: Codable, Hashable, Sendable {
        public var id: String
        public var date: String
        public var startedAt: Date
        public var durationSeconds: Double?
        public var name: String
        public var focus: String?
        public var source: String
        public var sessionRPE: Double?
        public var notes: String?
        public var exercises: [Entry]
    }

    public struct Entry: Codable, Hashable, Sendable {
        public var exercise: String
        public var notes: String?
        public var sets: [SetInfo]
        /// `false` when the exercise was left unfinished and the app ignores it for progression. Optional, added
        /// after v1 shipped; absent means it counts.
        public var countsForProgression: Bool?
    }

    /// `kind` is absent for working sets, otherwise `warmup`, `dropSet` or `failure`.
    public struct SetInfo: Codable, Hashable, Sendable {
        public var kind: String?
        public var weightKg: Double?
        public var reps: Int?
        public var rpe: Double?
        public var durationSeconds: Double?
        public var distanceMeters: Double?
    }

    public struct ExerciseTrend: Codable, Hashable, Sendable {
        public var exercise: String
        /// Sessions with this exercise in the period.
        public var exposures: Int
        /// The app's assessment over the last year: `progressing`, `holding`, `stalled` or `notEnoughData`.
        public var status: String
        public var lastWorkingWeightKg: Double?
        /// Best estimated one-rep max of each session in the period (Epley-style estimate from weight × reps).
        public var estimatedOneRepMaxKg: [Point]
    }

    public struct Point: Codable, Hashable, Sendable {
        public var date: String
        public var kg: Double
    }

    public struct CheckInInfo: Codable, Hashable, Sendable {
        public var date: String
        public var isSick: Bool
        /// 1–5.
        public var energy: Int?
        /// 1–5.
        public var soreness: Int?
        public var note: String?
    }

    public struct Metrics: Codable, Hashable, Sendable {
        public var date: String
        public var source: String
        public var hrvMs: Double?
        public var hrvBaselineLowMs: Double?
        public var hrvBaselineHighMs: Double?
        public var restingHeartRate: Double?
        public var sleepSeconds: Double?
        public var deepSleepSeconds: Double?
        public var remSleepSeconds: Double?
        public var sleepScore: Double?
        public var bodyBatteryHigh: Double?
        public var bodyBatteryLow: Double?
        public var averageStress: Double?
        public var steps: Int?
        public var vo2Max: Double?
        public var trainingReadiness: Double?
        public var acuteLoad: Double?
        public var recoveryTimeHours: Double?
    }

    public struct Run: Codable, Hashable, Sendable {
        public var date: String
        public var startedAt: Date
        public var name: String?
        public var source: String
        public var durationSeconds: Double
        public var distanceMeters: Double
        public var paceSecondsPerKm: Double?
        public var averageHeartRate: Double?
        public var maxHeartRate: Double?
        public var elevationGainMeters: Double?
        public var trainingLoad: Double?
        public var aerobicTrainingEffect: Double?
        public var anaerobicTrainingEffect: Double?
    }
}
