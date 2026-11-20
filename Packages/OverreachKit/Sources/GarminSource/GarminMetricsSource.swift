import Domain
import Foundation

/// Reads Garmin metrics through the official Garmin Connect Personal API (ADR-0022,
/// docs/design/garmin-integration.md).
///
/// Phase 2 implements: the user's own Personal API key in the Keychain, exchanged for a 24 h token, and requests
/// made directly from the iPhone (no intermediate server). It imports HRV (average, 5-minute high, status,
/// baseline), sleep stages and score, resting HR, stress, Body Battery, respiration, SpO2, VO2max and activities.
/// Training readiness and status are not available from this API. All fields are optional.
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
