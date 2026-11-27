import Domain
import Foundation

extension ContextPack {
    public struct Walk: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var durationSeconds: Double
        public var source: String
        public var steps: Int?
        public var distanceMeters: Double?
        public var elevationGainMeters: Double?
        public var averageHeartRate: Double?

        public init(_ walk: WalkBout) {
            startedAt = walk.start
            durationSeconds = walk.durationSeconds
            source = walk.source.rawValue
            steps = walk.steps
            distanceMeters = walk.distanceMeters
            elevationGainMeters = walk.elevationGainMeters
            averageHeartRate = walk.averageHeartRate
        }
    }

    public struct StrengthRecording: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var durationSeconds: Double
        public var source: String
        public var watch: Watch?

        public init(_ recording: RecordedStrengthActivity, watch: Watch) {
            startedAt = recording.startedAt
            durationSeconds = recording.durationSeconds
            source = recording.source.rawValue
            self.watch = watch
        }
    }
}
