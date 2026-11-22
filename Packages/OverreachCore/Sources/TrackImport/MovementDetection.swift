import Domain
import Foundation

/// A period in which the tracker was moving. Only these four values survive an import: no coordinates.
public struct MovementWindow: Hashable, Codable, Sendable {
    public var start: Date
    public var end: Date
    public var distanceMeters: Double
    public var confidence: CompanionWindow.Confidence

    public init(start: Date, end: Date, distanceMeters: Double, confidence: CompanionWindow.Confidence) {
        self.start = start
        self.end = end
        self.distanceMeters = distanceMeters
        self.confidence = confidence
    }

    /// The identity of a window: start and end rounded to the minute, so a re-import changes nothing.
    public var key: [Int] {
        [Int((start.timeIntervalSince1970 / 60).rounded()), Int((end.timeIntervalSince1970 / 60).rounded())]
    }

    /// The part the matcher needs.
    public var companionWindow: CompanionWindow {
        CompanionWindow(start: start, end: end, confidence: confidence)
    }
}

/// Turns timed positions into movement windows (docs/design/companion-walks.md#tractive-location-export-gpx-kml).
///
/// Thresholds are product heuristics, recorded with the matcher's as `walk-companion-matching` in docs/evidence.md.
enum MovementDetection {
    /// Slower than this between two points is standing still (GPS drift at home stays well below it).
    static let minimumSpeed = 0.5
    /// A window must last this long.
    static let minimumDuration: TimeInterval = 8 * 60
    /// Runs this close together are one window (the dog sniffs, the athlete waits at a crossing).
    static let joinGap: TimeInterval = 5 * 60
    /// Dense (Live mode) tracks are thinned to this spacing, so a few meters of drift in two seconds is not a run.
    static let minimumSpacing: TimeInterval = 30
    /// The collar reports at least once an hour while moving. A longer silence says nothing about movement.
    static let maximumSegment: TimeInterval = 3600
    /// Windows with a sparser track than this average interval only tag walks they overlap by a larger share.
    static let lowConfidenceInterval: TimeInterval = 5 * 60

    private struct Run {
        var firstIndex: Int
        var lastIndex: Int
        var distance: Double
    }

    static func windows(from points: [TrackPoint]) -> [MovementWindow] {
        let track = thinned(points)
        guard track.count >= 2 else { return [] }
        return joined(runs(in: track), in: track).compactMap { run -> MovementWindow? in
            let start = track[run.firstIndex].time
            let end = track[run.lastIndex].time
            let duration = end.timeIntervalSince(start)
            guard duration >= minimumDuration else { return nil }
            let intervals = Double(run.lastIndex - run.firstIndex)
            let confidence: CompanionWindow.Confidence = duration / intervals > lowConfidenceInterval ? .low : .normal
            return MovementWindow(start: start, end: end, distanceMeters: run.distance, confidence: confidence)
        }
    }

    /// Sorted by time, one point per instant, none closer than `minimumSpacing` to the one before it.
    private static func thinned(_ points: [TrackPoint]) -> [TrackPoint] {
        var result: [TrackPoint] = []
        for point in points.sorted(by: { $0.time < $1.time }) {
            if let last = result.last, point.time.timeIntervalSince(last.time) < minimumSpacing { continue }
            result.append(point)
        }
        return result
    }

    /// Maximal runs of consecutive moving segments.
    private static func runs(in track: [TrackPoint]) -> [Run] {
        var result: [Run] = []
        var current: Run?
        for index in 0..<(track.count - 1) {
            let seconds = track[index + 1].time.timeIntervalSince(track[index].time)
            let meters = track[index].distance(to: track[index + 1])
            if seconds <= maximumSegment, meters / seconds >= minimumSpeed {
                if var run = current {
                    run.lastIndex = index + 1
                    run.distance += meters
                    current = run
                } else {
                    current = Run(firstIndex: index, lastIndex: index + 1, distance: meters)
                }
            } else if let run = current {
                result.append(run)
                current = nil
            }
        }
        if let run = current { result.append(run) }
        return result
    }

    private static func joined(_ runs: [Run], in track: [TrackPoint]) -> [Run] {
        var result: [Run] = []
        for run in runs {
            if var last = result.last,
                track[run.firstIndex].time.timeIntervalSince(track[last.lastIndex].time) <= joinGap
            {
                last.lastIndex = run.lastIndex
                last.distance += run.distance
                result[result.count - 1] = last
            } else {
                result.append(run)
            }
        }
        return result
    }
}
