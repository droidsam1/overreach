import Domain
import Foundation

/// Turns Garmin records into Overreach's domain values. Pure; units are already SI (ms, seconds, meters).
public enum GarminMapping {
    /// One `DailyMetrics` per day that has any Garmin value, sorted by day. Each source endpoint fills its own fields;
    /// where two carry the same value (respiration, SpO2), the daily summary wins over the sleep record.
    public static func dailyMetrics(
        hrv: [GarminHRVNight] = [],
        sleep: [GarminSleep] = [],
        summaries: [GarminDailySummary] = [],
        vo2Max: [GarminVO2Max] = []
    ) -> [DailyMetrics] {
        var days: [CalendarDay: DailyMetrics] = [:]
        func update(_ day: CalendarDay, _ change: (inout DailyMetrics) -> Void) {
            var metrics = days[day] ?? DailyMetrics(day: day)
            change(&metrics)
            days[day] = metrics
        }

        for night in hrv {
            update(night.day) {
                $0.hrvRMSSDMs = night.lastNightAverage
                $0.hrvNightlyHighMs = night.lastNight5MinuteHigh
                $0.hrvBaselineLowMs = night.baselineBalancedLow
                $0.hrvBaselineHighMs = night.baselineBalancedUpper
                $0.hrvStatus = night.status
            }
        }
        for night in sleep where night.sleepSeconds != nil {
            update(night.day) {
                $0.sleepSeconds = night.sleepSeconds
                if let start = night.start, let end = night.end, start < end {
                    $0.sleepStart = start
                    $0.sleepEnd = end
                }
                $0.deepSleepSeconds = night.deepSeconds
                $0.lightSleepSeconds = night.lightSeconds
                $0.remSleepSeconds = night.remSeconds
                $0.awakeSeconds = night.awakeSeconds
                $0.sleepScore = night.score
                $0.respirationRate = night.averageRespiration
                $0.spo2Average = night.averageSpO2
            }
        }
        for summary in summaries {
            update(summary.day) {
                $0.restingHeartRate = summary.restingHeartRate
                $0.steps = summary.steps
                $0.averageStress = summary.averageStress
                $0.bodyBatteryHigh = summary.bodyBatteryHigh
                $0.bodyBatteryLow = summary.bodyBatteryLow
                $0.respirationRate = summary.averageRespiration ?? $0.respirationRate
                $0.spo2Average = summary.averageSpO2 ?? $0.spo2Average
            }
        }
        for estimate in vo2Max {
            update(estimate.day) { $0.vo2Max = estimate.value }
        }

        return days.values
            .filter(hasValues)
            .map { metrics in
                var metrics = metrics
                metrics.sources = [.garmin]
                return metrics
            }
            .sorted { $0.day < $1.day }
    }

    /// Runs of any kind (road, trail, treadmill, track, virtual).
    public static func runs(_ activities: [GarminActivity]) -> [RunActivity] {
        activities.filter(\.isRun).compactMap { activity in
            guard let duration = activity.durationSeconds, duration > 0 else { return nil }
            return RunActivity(
                id: activity.id,
                source: .garmin,
                name: activity.name,
                startedAt: activity.startedAt,
                durationSeconds: duration,
                distanceMeters: activity.distanceMeters ?? 0,
                averageHeartRate: activity.averageHeartRate,
                maxHeartRate: activity.maxHeartRate,
                elevationGainMeters: activity.elevationGainMeters,
                elevationLossMeters: activity.elevationLossMeters,
                averageCadence: activity.averageRunningCadence,
                trainingLoad: activity.trainingLoad,
                aerobicTrainingEffect: activity.aerobicTrainingEffect,
                anaerobicTrainingEffect: activity.anaerobicTrainingEffect,
                lapCount: activity.lapCount,
                movingDurationSeconds: activity.movingDurationSeconds,
                runWalk: activity.runWalk,
                elapsedSeconds: activity.elapsedSeconds,
                kind: runKind(activity)
            )
        }
        .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    private static func runKind(_ activity: GarminActivity) -> RunActivity.Kind {
        if activity.typeKey == "treadmill_running" || activity.typeKey == "virtual_running" { return .treadmill }
        if activity.eventTypeKey == "race" { return .race }
        return .training
    }

    /// Strength workouts recorded on the watch. They are paired with logged sessions by `StrengthActivityMatching`
    /// and never become sessions themselves.
    public static func strengthActivities(_ activities: [GarminActivity]) -> [RecordedStrengthActivity] {
        activities.filter(\.isStrength).compactMap { activity in
            guard let duration = activity.durationSeconds, duration > 0 else { return nil }
            return RecordedStrengthActivity(
                id: activity.id,
                source: .garmin,
                startedAt: activity.startedAt,
                durationSeconds: duration,
                averageHeartRate: activity.averageHeartRate,
                maxHeartRate: activity.maxHeartRate,
                trainingLoad: activity.trainingLoad,
                aerobicTrainingEffect: activity.aerobicTrainingEffect,
                anaerobicTrainingEffect: activity.anaerobicTrainingEffect,
                totalSets: activity.totalSets,
                totalReps: activity.totalReps
            )
        }
        .sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
    }

    /// Walking and hiking activities as walks (ADR-0010). Apple Health copies of the same walks are dropped later by
    /// `EverydayMovement.removingDuplicateWalks`, Garmin first.
    public static func walks(_ activities: [GarminActivity]) -> [GarminWalk] {
        activities.filter(\.isWalk).compactMap { activity in
            guard let duration = activity.durationSeconds, duration > 0 else { return nil }
            return GarminWalk(id: activity.id, walk: WalkBout(
                start: activity.startedAt,
                durationSeconds: duration,
                steps: activity.steps,
                distanceMeters: activity.distanceMeters,
                averageHeartRate: activity.averageHeartRate,
                elevationGainMeters: activity.elevationGainMeters,
                source: .garmin
            ))
        }
        .sorted { ($0.walk.start, $0.id) < ($1.walk.start, $1.id) }
    }

    private static func hasValues(_ metrics: DailyMetrics) -> Bool {
        var empty = DailyMetrics(day: metrics.day)
        empty.sources = metrics.sources
        return metrics != empty
    }
}
