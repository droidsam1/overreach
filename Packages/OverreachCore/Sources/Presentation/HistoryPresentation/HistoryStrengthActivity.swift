import Domain
import Foundation
import PresentationKit

/// A logged session or an unmatched workout from a watch, in the same timeline.
public enum HistoryRow: Identifiable, Sendable {
    public enum Identifier: Hashable, Sendable {
        case session(UUID)
        case recording(String)
    }

    case session(SessionSummary)
    case recording(HistoryStrengthActivity)

    public var id: Identifier {
        switch self {
        case let .session(summary): .session(summary.id)
        case let .recording(activity): .recording(activity.id)
        }
    }

    var date: Date {
        switch self {
        case let .session(summary): summary.date
        case let .recording(activity): activity.startedAt
        }
    }
}

/// Read-only display values from a watch, also shown alongside the matched session's logged sets.
public struct HistoryStrengthActivity: Identifiable, Sendable {
    public struct Metric: Identifiable, Sendable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    public let id: String
    public let source: String
    public let startedAt: Date
    public let durationSeconds: Double
    public let metrics: [Metric]

    public var title: String { L10n.text("Strength workout") }
    public var subtitle: String { L10n.format("{1} · No logged session", source) }

    init(_ activity: RecordedStrengthActivity, format: Format) {
        id = activity.id
        source = activity.source.displayName
        startedAt = activity.startedAt
        durationSeconds = activity.durationSeconds
        metrics = [
            activity.averageHeartRate.map {
                Metric(label: L10n.text("Average heart rate"), value: format.number($0, maxFractionDigits: 0) + " bpm")
            },
            activity.maxHeartRate.map {
                Metric(label: L10n.text("Maximum heart rate"), value: format.number($0, maxFractionDigits: 0) + " bpm")
            },
            activity.trainingLoad.map {
                Metric(label: L10n.text("Training load"), value: format.number($0))
            },
            activity.aerobicTrainingEffect.map {
                Metric(label: L10n.text("Aerobic training effect"), value: format.number($0, maxFractionDigits: 1))
            },
            activity.anaerobicTrainingEffect.map {
                Metric(label: L10n.text("Anaerobic training effect"), value: format.number($0, maxFractionDigits: 1))
            }
        ].compactMap { $0 }
    }
}
