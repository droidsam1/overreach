import Domain
import Foundation

// Garmin Connect Personal API responses, reduced to what Overreach uses (ADR-0022,
// docs/design/garmin-integration.md). Field names follow Garmin's OpenAPI document. Every value is optional: models
// differ, Garmin omits and nulls fields freely, and one field Garmin changes must never drop a whole record.

/// One night of HRV (`/hrv-service/hrv/daily/{from}/{to}`, `hrvSummaries[]`). Values in ms (nightly RMSSD).
public struct GarminHRVNight: Hashable, Sendable {
    public var day: CalendarDay
    public var lastNightAverage: Double?
    public var lastNight5MinuteHigh: Double?
    public var weeklyAverage: Double?
    public var baselineBalancedLow: Double?
    public var baselineBalancedUpper: Double?
    /// Garmin label: `BALANCED`, `UNBALANCED`, `LOW`, `POOR`. `NONE` and `INVALID` become nil.
    public var status: String?

    public init(
        day: CalendarDay,
        lastNightAverage: Double? = nil,
        lastNight5MinuteHigh: Double? = nil,
        weeklyAverage: Double? = nil,
        baselineBalancedLow: Double? = nil,
        baselineBalancedUpper: Double? = nil,
        status: String? = nil
    ) {
        self.day = day
        self.lastNightAverage = lastNightAverage
        self.lastNight5MinuteHigh = lastNight5MinuteHigh
        self.weeklyAverage = weeklyAverage
        self.baselineBalancedLow = baselineBalancedLow
        self.baselineBalancedUpper = baselineBalancedUpper
        self.status = status
    }
}

/// One night of sleep (`/sleep-service/sleep/dailySleepSummariesByDate`). `day` is the morning it ended.
public struct GarminSleep: Hashable, Sendable {
    public var day: CalendarDay
    public var start: Date?
    public var end: Date?
    public var sleepSeconds: Double?
    public var deepSeconds: Double?
    public var lightSeconds: Double?
    public var remSeconds: Double?
    public var awakeSeconds: Double?
    /// 0–100.
    public var score: Double?
    public var averageRespiration: Double?
    public var averageSpO2: Double?

    public init(
        day: CalendarDay,
        start: Date? = nil,
        end: Date? = nil,
        sleepSeconds: Double? = nil,
        deepSeconds: Double? = nil,
        lightSeconds: Double? = nil,
        remSeconds: Double? = nil,
        awakeSeconds: Double? = nil,
        score: Double? = nil,
        averageRespiration: Double? = nil,
        averageSpO2: Double? = nil
    ) {
        self.day = day
        self.start = start
        self.end = end
        self.sleepSeconds = sleepSeconds
        self.deepSeconds = deepSeconds
        self.lightSeconds = lightSeconds
        self.remSeconds = remSeconds
        self.awakeSeconds = awakeSeconds
        self.score = score
        self.averageRespiration = averageRespiration
        self.averageSpO2 = averageSpO2
    }
}

/// One day of the daily summary (`/usersummary-service/v2/dailysummaries`, `data[]`).
public struct GarminDailySummary: Hashable, Sendable {
    public var day: CalendarDay
    public var restingHeartRate: Double?
    public var steps: Int?
    /// 0–100; Garmin's negative "not enough data" values become nil.
    public var averageStress: Double?
    public var bodyBatteryHigh: Double?
    public var bodyBatteryLow: Double?
    public var averageRespiration: Double?
    public var averageSpO2: Double?

    public init(
        day: CalendarDay,
        restingHeartRate: Double? = nil,
        steps: Int? = nil,
        averageStress: Double? = nil,
        bodyBatteryHigh: Double? = nil,
        bodyBatteryLow: Double? = nil,
        averageRespiration: Double? = nil,
        averageSpO2: Double? = nil
    ) {
        self.day = day
        self.restingHeartRate = restingHeartRate
        self.steps = steps
        self.averageStress = averageStress
        self.bodyBatteryHigh = bodyBatteryHigh
        self.bodyBatteryLow = bodyBatteryLow
        self.averageRespiration = averageRespiration
        self.averageSpO2 = averageSpO2
    }
}

/// A VO2max estimate on the day it changed (`/metrics-service/metrics/maxmet/daily/{start}/{end}`, `generic`).
public struct GarminVO2Max: Hashable, Sendable {
    public var day: CalendarDay
    public var value: Double

    public init(
        day: CalendarDay,
        value: Double
    ) {
        self.day = day
        self.value = value
    }
}

/// An activity summary (`/activitylist-service/activities/search/activities`).
public struct GarminActivity: Hashable, Sendable {
    public var id: String
    /// Garmin activity type key, e.g. `running`, `trail_running`, `strength_training`.
    public var typeKey: String?
    public var name: String?
    public var startedAt: Date
    public var durationSeconds: Double?
    public var distanceMeters: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var elevationGainMeters: Double?
    public var elevationLossMeters: Double?
    public var averageRunningCadence: Double?
    public var trainingLoad: Double?
    public var aerobicTrainingEffect: Double?
    public var anaerobicTrainingEffect: Double?
    public var totalSets: Int?
    public var totalReps: Int?
    public var steps: Int?
    public var lapCount: Int?
    public var movingDurationSeconds: Double?
    public var runWalk: RunWalkSplits?
    public var elapsedSeconds: Double?
    public var eventTypeKey: String?

    public init(
        id: String,
        typeKey: String? = nil,
        name: String? = nil,
        startedAt: Date,
        durationSeconds: Double? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        elevationGainMeters: Double? = nil,
        elevationLossMeters: Double? = nil,
        averageRunningCadence: Double? = nil,
        trainingLoad: Double? = nil,
        aerobicTrainingEffect: Double? = nil,
        anaerobicTrainingEffect: Double? = nil,
        totalSets: Int? = nil,
        totalReps: Int? = nil,
        steps: Int? = nil,
        lapCount: Int? = nil,
        movingDurationSeconds: Double? = nil,
        runWalk: RunWalkSplits? = nil,
        elapsedSeconds: Double? = nil,
        eventTypeKey: String? = nil
    ) {
        self.id = id
        self.typeKey = typeKey
        self.name = name
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.averageRunningCadence = averageRunningCadence
        self.trainingLoad = trainingLoad
        self.aerobicTrainingEffect = aerobicTrainingEffect
        self.anaerobicTrainingEffect = anaerobicTrainingEffect
        self.totalSets = totalSets
        self.totalReps = totalReps
        self.steps = steps
        self.lapCount = lapCount
        self.movingDurationSeconds = movingDurationSeconds
        self.runWalk = runWalk
        self.elapsedSeconds = elapsedSeconds
        self.eventTypeKey = eventTypeKey
    }

    public var isRun: Bool { typeKey?.contains("run") ?? false }
    public var isStrength: Bool { typeKey?.contains("strength") ?? false }
    /// Walks and hikes of any kind (`walking`, `casual_walking`, `speed_walking`, `hiking`, …), never a run.
    public var isWalk: Bool {
        guard let typeKey, !isRun else { return false }
        return typeKey.contains("walk") || typeKey.contains("hik")
    }
}

/// A Garmin walking or hiking activity, kept with its activity id so a later sync replaces it instead of adding it
/// twice.
public struct GarminWalk: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var walk: WalkBout

    public init(id: String, walk: WalkBout) {
        self.id = id
        self.walk = walk
    }
}
