import Domain
import Foundation
import HealthKit

/// Reads recovery metrics and runs from Apple Health (phase 2) and writes strength workouts (phase 1).
///
/// Garmin Connect writes heart rate, resting heart rate, sleep, steps and activities to Health, but not HRV
/// in Garmin's RMSSD form — that comes from `GarminSource`. An Apple Watch user gets HRV (SDNN) from here.
public struct HealthKitMetricsSource: MetricsSource {
    public let kind: DataSourceKind = .appleHealth

    public init() {}

    public func isAvailable() async -> Bool {
        HKHealthStore.isHealthDataAvailable()
        // TODO(phase 2): also check that the user granted read access to the types we need.
    }

    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        // TODO(phase 2): query resting HR, HRV (SDNN), sleep analysis, steps; aggregate per CalendarDay.
        []
    }

    public func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        // TODO(phase 2): query HKWorkout with activity type .running and map to RunActivity.
        []
    }
}
