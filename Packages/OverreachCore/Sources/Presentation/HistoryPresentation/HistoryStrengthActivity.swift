import Domain
import Foundation
import PresentationKit

/// The activity filter used by the unified list.
public enum HistoryActivityFilter: String, CaseIterable, Identifiable, Sendable {
    case all, strength, running, walking

    public var id: Self { self }
    public var title: String {
        switch self {
        case .all: L10n.text("All activities")
        case .strength: L10n.text("Strength")
        case .running: L10n.text("Runs")
        case .walking: L10n.text("Walking")
        }
    }
}

/// A logged session, watch-only strength workout or run, in the same timeline.
public enum HistoryRow: Identifiable, Sendable {
    public enum Identifier: Hashable, Sendable {
        case session(UUID)
        case recording(StrengthRecordingID)
        case run(String)
        case walk(WalkKey)
    }

    case session(SessionSummary)
    case recording(HistoryStrengthActivity)
    case run(HistoryRunActivity)
    case walk(HistoryWalk)

    public var id: Identifier {
        switch self {
        case let .session(summary): .session(summary.id)
        case let .recording(activity): .recording(activity.recordingID)
        case let .run(activity): .run(activity.id)
        case let .walk(activity): .walk(activity.id)
        }
    }

    var date: Date {
        switch self {
        case let .session(summary): summary.date
        case let .recording(activity): activity.startedAt
        case let .run(activity): activity.startedAt
        case let .walk(activity): activity.walk.start
        }
    }

    var activityFilter: HistoryActivityFilter {
        switch self {
        case .session, .recording: .strength
        case .run: .running
        case .walk: .walking
        }
    }

    var sources: [DataSourceKind] {
        switch self {
        case let .session(summary): summary.sources
        case let .recording(activity): activity.sources
        case let .run(activity): activity.sources
        case let .walk(activity): activity.sources
        }
    }

    var sortID: String {
        switch id {
        case let .session(id): "session:" + id.uuidString
        case let .recording(id): "recording:\(id.source.rawValue):\(id.id)"
        case let .run(id): "run:" + id
        case let .walk(id): "walk:\(id.source.rawValue):\(id.startSeconds)"
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
public struct HistoryStrengthActivity: Identifiable, Hashable, Sendable {
    public let id: String
    public let recordingID: StrengthRecordingID
    let sources: [DataSourceKind]
    public var source: String { sources.map(\.displayName).joined(separator: " · ") }
    public let startedAt: Date
    public let durationSeconds: Double
    public let metrics: [HistoryMetric]

    public var title: String { L10n.text("Strength workout") }
    public var subtitle: String { L10n.format("{1} · No logged session", source) }

    init(_ activity: RecordedStrengthActivity, sources: [DataSourceKind]? = nil, format: Format) {
        id = activity.id
        recordingID = StrengthRecordingID(activity)
        self.sources = sources ?? [activity.source]
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

public struct HistoryStrengthReview: Identifiable, Sendable {
    public let id: StrengthMatchPair
    public let sessionName: String
    public let sessionSource: String
    public let sessionStart: Date
    public let sessionDuration: Double?
    public let recording: HistoryStrengthActivity
    public let isSeparate: Bool

    init(_ candidate: StrengthMatchCandidate, format: Format) {
        id = candidate.pair
        sessionName = candidate.session.name
        sessionSource = candidate.session.source.displayName
        sessionStart = candidate.session.startedAt
        sessionDuration = candidate.session.durationSeconds
        recording = HistoryStrengthActivity(candidate.recording, format: format)
        isSeparate = candidate.isSeparate
    }
}
