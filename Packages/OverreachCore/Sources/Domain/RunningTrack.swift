import Foundation

/// Time-stamped measurements from one recorded running activity.
public struct RunningTrack: Equatable, Sendable {
    public struct Sample: Equatable, Sendable {
        public let date: Date
        public let distanceMeters: Double?
        public let speedMetersPerSecond: Double?
        public let altitudeMeters: Double?
        public let heartRateBPM: Double?
        public let cadenceStepsPerMinute: Double?
        public let latitude: Double?
        public let longitude: Double?

        public init(
            date: Date, distanceMeters: Double? = nil, speedMetersPerSecond: Double? = nil,
            altitudeMeters: Double? = nil, heartRateBPM: Double? = nil, cadenceStepsPerMinute: Double? = nil,
            latitude: Double? = nil, longitude: Double? = nil
        ) {
            self.date = date
            self.distanceMeters = distanceMeters
            self.speedMetersPerSecond = speedMetersPerSecond
            self.altitudeMeters = altitudeMeters
            self.heartRateBPM = heartRateBPM
            self.cadenceStepsPerMinute = cadenceStepsPerMinute
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public enum BoundaryKind: Equatable, Sendable {
        case manualLap, automaticLap, timerStart, timerStop
    }

    public struct Boundary: Equatable, Sendable {
        public let date: Date
        public let kind: BoundaryKind

        public init(date: Date, kind: BoundaryKind) {
            self.date = date
            self.kind = kind
        }
    }

    public let samples: [Sample]
    public let boundaries: [Boundary]
    /// Identity of the actual heart rate source when the recorder verifies it.
    public let heartRateSensorID: String?

    public init(samples: [Sample], boundaries: [Boundary] = [], heartRateSensorID: String? = nil) {
        self.samples = samples
        self.boundaries = boundaries
        self.heartRateSensorID = heartRateSensorID
    }
}
