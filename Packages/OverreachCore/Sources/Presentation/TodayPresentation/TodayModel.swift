import Domain
import Foundation
import Observation
import PresentationKit

/// State and actions of the Today screen (ADR-0003, ADR-0014): dependencies come in as `Domain` protocols, the
/// view only reads state and calls actions.
@MainActor
@Observable
public final class TodayModel {
    public private(set) var metrics: DailyMetrics?
    /// The last 7 days (today included), merged across sources, oldest first. Days without data are left out.
    public private(set) var week: [DailyMetrics] = []
    public private(set) var readiness = Readiness(level: .unknown, reasons: [.missingData])
    public private(set) var isLoading = false
    /// Sources that failed during the last load. The screen still shows whatever the others returned.
    public private(set) var failedSources: [DataSourceKind] = []

    private let sources: [any MetricsSource]
    private let calendar: Calendar
    private let format: Format

    // MARK: Screen state

    public var readinessLevel: ReadinessLevel { readiness.level }
    public var readinessTitle: String { readiness.level.displayName }

    public var hrvMs: Double? { metrics?.hrvNightlyAverageMs }
    public var restingHeartRate: Double? { metrics?.restingHeartRate }
    /// Sleep in hours (stored in seconds).
    public var sleepHours: Double? { metrics?.sleepSeconds.map { $0 / 3_600 } }
    public var bodyBattery: Double? { metrics?.bodyBatteryHigh }
    public var steps: Double? { metrics?.steps.map(Double.init) }
    public var vo2Max: Double? { metrics?.vo2Max }
    /// Body Battery is Garmin's: the tile only shows when there is a value.
    public var showsBodyBattery: Bool { bodyBattery != nil }
    public var showsVO2Max: Bool { vo2Max != nil }

    /// "Deep 1.2 h · REM 1.6 h".
    public var sleepCaption: String? {
        guard let metrics, metrics.deepSleepSeconds != nil || metrics.remSleepSeconds != nil else { return nil }
        let hours = { (seconds: Double?) in self.format.number((seconds ?? 0) / 3_600, maxFractionDigits: 1) }
        return L10n.format("Deep {1} h · REM {2} h", hours(metrics.deepSleepSeconds), hours(metrics.remSleepSeconds))
    }

    /// "7-day avg 42 ms", from the days that have a value.
    public var hrvCaption: String? { average(\.hrvNightlyAverageMs).map { weekly(format.number($0, maxFractionDigits: 0) + " ms") } }
    public var restingHeartRateCaption: String? {
        average(\.restingHeartRate).map { weekly(format.number($0, maxFractionDigits: 0) + " bpm") }
    }
    public var sleepAverageCaption: String? {
        average(\.sleepSeconds).map { weekly(format.number($0 / 3_600, maxFractionDigits: 1) + " h") }
    }
    public var stepsCaption: String? {
        average { $0.steps.map(Double.init) }.map { weekly(format.number($0, maxFractionDigits: 0)) }
    }

    /// "From Apple Health · Garmin" — where today's numbers come from.
    public var sourcesText: String? {
        guard let metrics, !metrics.sources.isEmpty else { return nil }
        let names = DataSourceKind.allCases.filter(metrics.sources.contains).map(\.displayName)
        return L10n.format("From {1}", names.joined(separator: " · "))
    }

    public var showsLoadingIndicator: Bool { isLoading && metrics == nil }
    public var showsSourceWarning: Bool { !failedSources.isEmpty }
    public var showsNoDataHint: Bool { !isLoading && metrics == nil && failedSources.isEmpty }
    /// The "Connect Apple Health" button: shown while there is nothing to display.
    public var showsConnectHealth: Bool { !isLoading && metrics == nil }

    /// - Parameter sources: metric sources in priority order. When two sources report the same value,
    ///   the first one wins (e.g. `[garmin, appleHealth]`).
    public init(sources: [any MetricsSource], calendar: Calendar = .current, format: Format = Format()) {
        self.sources = sources
        self.calendar = calendar
        self.format = format
    }

    public func load(now: Date = .now) async {
        isLoading = true
        defer { isLoading = false }

        let today = CalendarDay(now, calendar: calendar)
        let range = today.adding(days: -6, calendar: calendar)...today
        var byDay: [CalendarDay: DailyMetrics] = [:]
        var failures: [DataSourceKind] = []

        for source in sources {
            guard await source.isAvailable() else { continue }
            do {
                for day in try await source.dailyMetrics(in: range) where range.contains(day.day) {
                    byDay[day.day] = (byDay[day.day] ?? DailyMetrics(day: day.day)).merging(day)
                }
            } catch {
                failures.append(source.kind)
            }
        }

        week = byDay.values.filter { !$0.sources.isEmpty }.sorted { $0.day < $1.day }
        metrics = byDay[today].flatMap { $0.sources.isEmpty ? nil : $0 }
        failedSources = failures
        // TODO(phase 2): compute readiness with the Analytics rules engine (evidence review first, ADR-0012).
    }

    /// Asks every source for access (the Apple Health permission sheet), then reloads.
    public func connectHealth(now: Date = .now) async {
        for source in sources {
            await source.requestAccess()
        }
        await load(now: now)
    }

    private func average(_ value: (DailyMetrics) -> Double?) -> Double? {
        let values = week.compactMap(value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func weekly(_ value: String) -> String {
        L10n.format("7-day avg {1}", value)
    }
}
