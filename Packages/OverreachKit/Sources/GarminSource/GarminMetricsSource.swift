import Domain
import Foundation

/// Reads Garmin-only metrics from Garmin Connect through its unofficial API (ADR-0005).
///
/// Phase 2 implements: one-time sign-in, OAuth tokens in the Keychain, and requests made directly from
/// the iPhone (no intermediate server). Import every metric the watch provides — HRV (average, 5-minute
/// high, status, baseline), Body Battery, stress, respiration, SpO2, sleep stages and score, training
/// status and readiness, acute load, recovery time, VO2max and activity details. All fields are optional.
///
/// This module is optional: when it is not configured or Garmin changes the API, the app keeps working
/// with Apple Health and the daily check-in.
public struct GarminMetricsSource: MetricsSource {
    public let kind: DataSourceKind = .garmin

    public init() {}

    public func isAvailable() async -> Bool {
        // TODO(phase 2): true when valid tokens exist in the Keychain.
        false
    }

    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        []
    }

    public func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        []
    }
}
