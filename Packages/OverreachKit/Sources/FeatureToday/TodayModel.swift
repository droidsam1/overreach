import Domain
import Foundation
import Observation

/// State and actions of the Today screen. Reference implementation of the feature pattern (ADR-0003):
/// dependencies come in as `Domain` protocols, the view only reads state and calls actions.
@MainActor
@Observable
public final class TodayModel {
    public private(set) var metrics: DailyMetrics?
    public private(set) var readiness = Readiness(level: .unknown, reasons: [.missingData])
    public private(set) var isLoading = false
    /// Sources that failed during the last load. The screen still shows whatever the others returned.
    public private(set) var failedSources: [DataSourceKind] = []

    private let sources: [any MetricsSource]
    private let calendar: Calendar

    /// - Parameter sources: metric sources in priority order. When two sources report the same value,
    ///   the first one wins (e.g. `[garmin, appleHealth]`).
    public init(sources: [any MetricsSource], calendar: Calendar = .current) {
        self.sources = sources
        self.calendar = calendar
    }

    public func load(now: Date = .now) async {
        isLoading = true
        defer { isLoading = false }

        let today = CalendarDay(now, calendar: calendar)
        var merged = DailyMetrics(day: today)
        var failures: [DataSourceKind] = []

        for source in sources {
            guard await source.isAvailable() else { continue }
            do {
                let days = try await source.dailyMetrics(in: today...today)
                if let match = days.first(where: { $0.day == today }) {
                    merged = merged.merging(match)
                }
            } catch {
                failures.append(source.kind)
            }
        }

        metrics = merged.sources.isEmpty ? nil : merged
        failedSources = failures
        // TODO(phase 2): compute readiness with the Analytics rules engine.
    }
}
