import Domain
import Foundation

/// Values read from several sources, with which sources answered and which failed (ADR-0035).
public struct SourceReading<Value: Sendable>: Sendable {
    public var value: Value
    /// Available sources that answered, in source order.
    public var readSources: [DataSourceKind]
    /// Available sources that threw, in source order, with the error's description.
    public var failures: [SourceFailure]

    public init(value: Value, readSources: [DataSourceKind] = [], failures: [SourceFailure] = []) {
        self.value = value
        self.readSources = readSources
        self.failures = failures
    }

    /// At least one available source answered.
    public var didRead: Bool { !readSources.isEmpty }
    /// At least one available source failed.
    public var failed: Bool { !failures.isEmpty }
    public var failedSources: [DataSourceKind] { failures.map(\.source) }
}

public struct SourceFailure: Hashable, Sendable {
    public var source: DataSourceKind
    public var reason: String

    public init(source: DataSourceKind, reason: String) {
        self.source = source
        self.reason = reason
    }
}

/// The one way Overreach reads metrics and runs from its sources (ADR-0035): unavailable sources are skipped, an
/// available source that throws is a failure that leaves the other sources' values visible, daily metrics are merged
/// per day in source order (the first source wins, Garmin before Apple Health) and each run appears once.
public struct SourceReader: Sendable {
    private let sources: [any MetricsSource]

    /// - Parameter sources: in priority order; when two report the same value, the first wins.
    public init(sources: [any MetricsSource]) {
        self.sources = sources
    }

    /// One merged record per day in `range` that some source reported, oldest first: what Today judges.
    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async -> SourceReading<[DailyMetrics]> {
        let reading = await dailyMetricsBySource(in: range)
        var byDay: [CalendarDay: DailyMetrics] = [:]
        for day in reading.value {
            byDay[day.day] = (byDay[day.day] ?? DailyMetrics(day: day.day)).merging(day)
        }
        let merged = byDay.values.filter { !$0.sources.isEmpty }.sorted { $0.day < $1.day }
        return SourceReading(value: merged, readSources: reading.readSources, failures: reading.failures)
    }

    /// Each source's own records in `range`, by day and then in source order, unmerged: for the AI context, which
    /// shows every source's values side by side (`docs/ai-exchange.md`).
    public func dailyMetricsBySource(in range: ClosedRange<CalendarDay>) async -> SourceReading<[DailyMetrics]> {
        let results = await read { try await $0.dailyMetrics(in: range) }
        let rows = results.value.enumerated().flatMap { index, days in
            days.filter { range.contains($0.day) }.map { (index, $0) }
        }
        .sorted { ($0.1.day, $0.0) < ($1.1.day, $1.0) }
        .map(\.1)
        return SourceReading(value: rows, readSources: results.readSources, failures: results.failures)
    }

    /// Runs started in the range, each run once with every source that recorded it, oldest first.
    public func runs(from start: Date, to end: Date) async -> SourceReading<[RunDeduplication.CombinedRun]> {
        let results = await read { try await $0.runs(from: start, to: end) }
        return SourceReading(
            value: RunDeduplication.combiningSources(results.value.flatMap { $0 }),
            readSources: results.readSources, failures: results.failures
        )
    }

    /// Reads every available source in parallel and returns the answers in source order.
    private func read<Value: Sendable>(
        _ request: @escaping @Sendable (any MetricsSource) async throws -> Value
    ) async -> SourceReading<[Value]> {
        let outcomes = await withTaskGroup(of: (Int, Outcome<Value>).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    guard await source.isAvailable() else { return (index, .unavailable) }
                    do {
                        return (index, .value(try await request(source)))
                    } catch {
                        return (index, .failure(error.localizedDescription))
                    }
                }
            }
            var outcomes: [Int: Outcome<Value>] = [:]
            for await (index, outcome) in group { outcomes[index] = outcome }
            return outcomes
        }
        var values: [Value] = []
        var readSources: [DataSourceKind] = []
        var failures: [SourceFailure] = []
        for (index, source) in sources.enumerated() {
            switch outcomes[index] {
            case let .value(value):
                values.append(value)
                readSources.append(source.kind)
            case let .failure(reason):
                failures.append(SourceFailure(source: source.kind, reason: reason))
            case .unavailable, nil:
                break
            }
        }
        return SourceReading(value: values, readSources: readSources, failures: failures)
    }
}

private enum Outcome<Value: Sendable>: Sendable {
    case unavailable
    case value(Value)
    case failure(String)
}

extension SourceReading where Value == [RunDeduplication.CombinedRun] {
    /// One record per run, the preferred source's copy with missing fields filled from the others.
    public var activities: [RunActivity] { value.map(\.activity) }
}
