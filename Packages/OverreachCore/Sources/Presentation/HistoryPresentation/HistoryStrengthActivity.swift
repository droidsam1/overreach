import Domain
import Foundation
import PresentationKit

/// The activity filter used by the unified list.
public enum HistoryActivityFilter: String, CaseIterable, Identifiable, Sendable {
    case all, strength, running

    public var id: Self { self }
    public var title: String {
        switch self {
        case .all: L10n.text("All activities")
        case .strength: L10n.text("Strength")
        case .running: L10n.text("Runs")
        }
    }
}

/// A logged session, watch-only strength workout or run, in the same timeline.
public enum HistoryRow: Identifiable, Sendable {
    public enum Identifier: Hashable, Sendable {
        case session(UUID)
        case recording(String)
        case run(String)
    }

    case session(SessionSummary)
    case recording(HistoryStrengthActivity)
    case run(HistoryRunActivity)

    public var id: Identifier {
        switch self {
        case let .session(summary): .session(summary.id)
        case let .recording(activity): .recording(activity.id)
        case let .run(activity): .run(activity.id)
        }
    }

    var date: Date {
        switch self {
        case let .session(summary): summary.date
        case let .recording(activity): activity.startedAt
        case let .run(activity): activity.startedAt
        }
    }

    var activityFilter: HistoryActivityFilter {
        switch self {
        case .session, .recording: .strength
        case .run: .running
        }
    }

    var sources: [DataSourceKind] {
        switch self {
        case let .session(summary): summary.sources
        case let .recording(activity): [activity.sourceKind]
        case let .run(activity): activity.sources
        }
    }

    var sortID: String {
        switch id {
        case let .session(id): "session:" + id.uuidString
        case let .recording(id): "recording:" + id
        case let .run(id): "run:" + id
        }
    }
}

/// One labeled value from a recorded workout.
public struct HistoryMetric: Identifiable, Hashable, Sendable {
    public let label: String
    public let value: String
    public var id: String { label }

    static func training(load: Double?, aerobic: Double?, anaerobic: Double?, format: Format) -> [Self] {
        [
            load.map {
                Self(label: L10n.text("Training load"), value: format.number($0))
            },
            aerobic.map {
                Self(label: L10n.text("Aerobic training effect"), value: format.number($0, maxFractionDigits: 1))
            },
            anaerobic.map {
                Self(label: L10n.text("Anaerobic training effect"), value: format.number($0, maxFractionDigits: 1))
            }
        ].compactMap { $0 }
    }
}

/// Read-only display values from a watch, also shown alongside the matched session's logged sets.
public struct HistoryStrengthActivity: Identifiable, Sendable {
    public let id: String
    let sourceKind: DataSourceKind
    public var source: String { sourceKind.displayName }
    public let startedAt: Date
    public let durationSeconds: Double
    public let metrics: [HistoryMetric]

    public var title: String { L10n.text("Strength workout") }
    public var subtitle: String { L10n.format("{1} · No logged session", source) }

    init(_ activity: RecordedStrengthActivity, format: Format) {
        id = activity.id
        sourceKind = activity.source
        startedAt = activity.startedAt
        durationSeconds = activity.durationSeconds
        metrics = [
            activity.averageHeartRate.map {
                HistoryMetric(
                    label: L10n.text("Average heart rate"), value: format.number($0, maxFractionDigits: 0) + " bpm"
                )
            },
            activity.maxHeartRate.map {
                HistoryMetric(
                    label: L10n.text("Maximum heart rate"), value: format.number($0, maxFractionDigits: 0) + " bpm"
                )
            }
        ].compactMap { $0 } + HistoryMetric.training(
            load: activity.trainingLoad, aerobic: activity.aerobicTrainingEffect,
            anaerobic: activity.anaerobicTrainingEffect, format: format
        )
    }
}
