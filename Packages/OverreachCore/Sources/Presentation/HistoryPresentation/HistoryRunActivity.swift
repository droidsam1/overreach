import Domain
import Foundation
import PresentationKit
import TrainingServices

/// Display values for a run in the timeline, calendar and activity detail.
public struct HistoryRunActivity: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startedAt: Date
    public let sources: [DataSourceKind]
    public let distance: String
    public let duration: String
    public let pace: String?
    public let heartRate: String?
    public let trainingMetrics: [HistoryMetric]

    public var source: String { sources.first?.displayName ?? "" }
    public var sourceText: String { sources.map(\.displayName).joined(separator: " · ") }

    init(_ combined: RunDeduplication.CombinedRun, format: Format) {
        let run = combined.activity
        id = "\(run.source.rawValue):\(run.id)"
        title = run.name ?? L10n.text("Run")
        startedAt = run.startedAt
        sources = combined.sources
        distance = format.number(run.distanceMeters / 1_000, maxFractionDigits: 2) + " km"
        duration = Self.clockText(seconds: Int(run.durationSeconds.rounded()), format: format)
        pace = run.paceSecondsPerKm.map { format.minutesAndSeconds(Int($0.rounded())) + " /km" }
        heartRate = run.averageHeartRate.map { format.number($0, maxFractionDigits: 0) + " bpm" }
        trainingMetrics = HistoryMetric.training(
            load: run.trainingLoad, aerobic: run.aerobicTrainingEffect,
            anaerobic: run.anaerobicTrainingEffect, format: format
        )
    }

    private static func clockText(seconds: Int, format: Format) -> String {
        let hours = seconds / 3_600
        guard hours > 0 else { return format.minutesAndSeconds(seconds) }
        let rest = format.minutesAndSeconds(seconds % 3_600)
        return "\(hours):\(rest.count < 5 ? "0" : "")\(rest)"
    }
}

/// Runs for History from `SourceReader` (ADR-0035). A failure in one source leaves the successful reads visible.
struct HistoryRunReadings: Sendable {
    let runs: [RunDeduplication.CombinedRun]
    let didRead: Bool
    let failedSources: Set<DataSourceKind>

    func warning(excluding excluded: Set<DataSourceKind> = []) -> String? {
        let failures = DataSourceKind.allCases.filter { failedSources.contains($0) && !excluded.contains($0) }
        guard !failures.isEmpty else { return nil }
        return L10n.format("Could not load runs from {1}.", failures.map(\.displayName).joined(separator: ", "))
    }

    static func load(sources: [any MetricsSource], from start: Date, to end: Date) async -> Self {
        let reading = await SourceReader(sources: sources).readRuns(from: start, to: end)
        return Self(runs: reading.value, didRead: reading.didRead, failedSources: Set(reading.failedSources))
    }
}
