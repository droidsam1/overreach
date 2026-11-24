import Domain
import Foundation

/// The Garmin Connect Personal API requests Overreach makes, with the per-request range limits Garmin documents
/// (OpenAPI 1.0.0, checked live on 2026-11-20). `GarminSource` sends them; building them here keeps them testable.
public enum GarminEndpoint: Hashable, Sendable {
    case hrv(ClosedRange<CalendarDay>)
    case sleep(ClosedRange<CalendarDay>)
    case dailySummaries(ClosedRange<CalendarDay>)
    case vo2Max(ClosedRange<CalendarDay>)
    /// One page of activities started in the range (`limit` per page).
    case activities(ClosedRange<CalendarDay>, start: Int, limit: Int)
    /// The laps of one activity. Not part of `GarminSyncPlan.requests`: the service asks for the recent runs that
    /// have none yet, a few per sync (`GarminSyncPlan.lapRefreshDays`, `maximumLapRequests`).
    case activitySplits(id: String)

    public static let host = "personal.connectapi.garmin.com"
    /// `POST` with `Authorization: ApiKey <key>`; the body of the response is the access token.
    public static let tokenPath = "/personalapitoken-service/personal-api/personal-api-key/token"
    /// Activities per page. Garmin's default is 99, but larger pages have returned errors.
    public static let activityPageSize = 40

    /// Longest range one request accepts, in days.
    public static func maximumDays(for kind: Kind) -> Int {
        switch kind {
        case .hrv, .dailySummaries, .vo2Max: 365
        case .sleep: 31
        case .activities: 365
        case .activitySplits: 1
        }
    }

    public enum Kind: Sendable, CaseIterable {
        case hrv, sleep, dailySummaries, vo2Max, activities, activitySplits
    }

    public var kind: Kind {
        switch self {
        case .hrv: .hrv
        case .sleep: .sleep
        case .dailySummaries: .dailySummaries
        case .vo2Max: .vo2Max
        case .activities: .activities
        case .activitySplits: .activitySplits
        }
    }

    /// Path and query, to append to `https://` + `host`.
    public var path: String {
        switch self {
        case let .hrv(range):
            "/hrv-service/hrv/daily/\(range.lowerBound)/\(range.upperBound)"
        case let .sleep(range):
            "/sleep-service/sleep/dailySleepSummariesByDate?startDate=\(range.lowerBound)&endDate=\(range.upperBound)"
        case let .dailySummaries(range):
            "/usersummary-service/v2/dailysummaries?startDate=\(range.lowerBound)&endDate=\(range.upperBound)"
        case let .vo2Max(range):
            "/metrics-service/metrics/maxmet/daily/\(range.lowerBound)/\(range.upperBound)"
        case let .activities(range, start, limit):
            "/activitylist-service/activities/search/activities?start=\(start)&limit=\(limit)"
                + "&startDate=\(range.lowerBound)&endDate=\(range.upperBound)"
        case let .activitySplits(id):
            "/activity-service/activity/\(id)/splits"
        }
    }
}

/// Which days to ask Garmin for, and in which windows. Pure.
public enum GarminSyncPlan {
    /// Days fetched on the first sync: enough for the 60-day readiness baselines (ADR-0020).
    public static let firstSyncDays = 60
    /// Recent days fetched again on every sync: the watch syncs late, and Garmin finalises a day after it ends.
    public static let refetchDays = 2
    /// A watch can upload a workout days after it was recorded. Always revisit the last week of activities.
    public static let activityRefetchDays = 7
    /// Laps are fetched only for runs this recent, and for at most `maximumLapRequests` runs per sync (newest first),
    /// so a sync costs at most that many requests more. Older runs keep what they have; ADR-0022 sets the budget.
    public static let lapRefreshDays = 14
    public static let maximumLapRequests = 5

    /// The days to fetch now, from the last day synced before (nil on the first sync) up to `today`.
    public static func range(
        lastSynced: CalendarDay?, today: CalendarDay, calendar: Calendar = .current
    ) -> ClosedRange<CalendarDay> {
        let earliest = today.adding(days: -(firstSyncDays - 1), calendar: calendar)
        guard let lastSynced, lastSynced <= today else { return earliest...today }
        let start = max(earliest, min(lastSynced, today.adding(days: -(refetchDays - 1), calendar: calendar)))
        return start...today
    }

    /// `range` cut into consecutive windows of at most `maximumDays` days, oldest first.
    public static func windows(
        _ range: ClosedRange<CalendarDay>, maximumDays: Int, calendar: Calendar = .current
    ) -> [ClosedRange<CalendarDay>] {
        let size = max(1, maximumDays)
        var windows: [ClosedRange<CalendarDay>] = []
        var start = range.lowerBound
        while start <= range.upperBound {
            let end = min(start.adding(days: size - 1, calendar: calendar), range.upperBound)
            windows.append(start...end)
            start = end.adding(days: 1, calendar: calendar)
        }
        return windows
    }

    /// Every request for `range`, split to Garmin's limits. Activity pages after the first are requested only when a
    /// page comes back full, so this returns the first page of each window.
    /// `activityDays`: how many days back activities are fetched at least (`activityRefetchDays` by default).
    public static func requests(
        for range: ClosedRange<CalendarDay>, activityDays: Int = activityRefetchDays, calendar: Calendar = .current
    ) -> [GarminEndpoint] {
        GarminEndpoint.Kind.allCases.flatMap { kind in
            let windowRange = kind == .activities
                ? activityRange(including: range, days: activityDays, calendar: calendar) : range
            return windows(windowRange, maximumDays: GarminEndpoint.maximumDays(for: kind), calendar: calendar)
                .compactMap { window in
                    switch kind {
                    case .hrv: GarminEndpoint.hrv(window)
                    case .sleep: GarminEndpoint.sleep(window)
                    case .dailySummaries: GarminEndpoint.dailySummaries(window)
                    case .vo2Max: GarminEndpoint.vo2Max(window)
                    case .activities: GarminEndpoint.activities(window, start: 0, limit: GarminEndpoint.activityPageSize)
                    case .activitySplits: nil
                    }
                }
        }
    }

    private static func activityRange(including range: ClosedRange<CalendarDay>, days: Int, calendar: Calendar)
        -> ClosedRange<CalendarDay> {
        let earliest = range.upperBound.adding(days: -(max(1, days) - 1), calendar: calendar)
        return min(earliest, range.lowerBound)...range.upperBound
    }
}
