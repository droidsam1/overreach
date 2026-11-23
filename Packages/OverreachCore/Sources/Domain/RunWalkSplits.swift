import Foundation

/// How the watch split a run into running, walking and standing (Garmin run/walk detection). Each part sums the
/// segments of that kind. Absent when the source does not detect it (Apple Health, older watches).
public struct RunWalkSplits: Hashable, Codable, Sendable {
    public struct Part: Hashable, Codable, Sendable {
        public var distanceMeters: Double
        public var durationSeconds: Double
        /// How many separate segments of this kind the run had.
        public var segments: Int
        /// The longest single segment, e.g. the longest continuous running stretch.
        public var longestSegmentMeters: Double?
        /// Steps per minute.
        public var averageCadence: Double?

        public init(
            distanceMeters: Double, durationSeconds: Double, segments: Int, longestSegmentMeters: Double? = nil,
            averageCadence: Double? = nil
        ) {
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.segments = segments
            self.longestSegmentMeters = longestSegmentMeters
            self.averageCadence = averageCadence
        }

        /// Seconds per kilometre over this part, if it covered any distance.
        public var paceSecondsPerKm: Double? {
            distanceMeters > 0 && durationSeconds > 0 ? durationSeconds / (distanceMeters / 1_000) : nil
        }

        /// A typical segment length, e.g. the usual walk break.
        public var averageSegmentMeters: Double? {
            segments > 0 && distanceMeters > 0 ? distanceMeters / Double(segments) : nil
        }
    }

    public var running: Part?
    public var walking: Part?
    public var standing: Part?

    public init(running: Part? = nil, walking: Part? = nil, standing: Part? = nil) {
        self.running = running
        self.walking = walking
        self.standing = standing
    }

    /// Share of the moving distance covered walking, from 0 to 1.
    public var walkingShare: Double? {
        let run = running?.distanceMeters ?? 0
        let walk = walking?.distanceMeters ?? 0
        return run + walk > 0 ? walk / (run + walk) : nil
    }
}
