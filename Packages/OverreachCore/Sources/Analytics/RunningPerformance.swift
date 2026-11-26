import Domain
import Foundation

public enum RunningPerformance {
    public static let calculationVersion = 1

    public enum Distance: Int, CaseIterable, Sendable {
        case oneKilometer = 1_000
        case fiveKilometers = 5_000
        case tenKilometers = 10_000
    }

    public enum Coverage: Equatable, Sendable {
        case lapBoundaries
        case wholeActivity
        case nearWholeActivity
        /// Fastest stretch of the recorded track, for activities whose laps do not cover the distance.
        case trackSamples
    }

    public struct BestTime: Equatable, Sendable {
        public let run: RunActivity
        public let distance: Distance
        public let elapsedSeconds: Double
        public let coverage: Coverage
        public let observedDistanceMeters: Double

        public var kind: RunActivity.Kind { run.kind ?? .unknown }
    }

    /// One elapsed result per canonical activity, fastest first. Resolve cross-source matches and explicit
    /// separations before calling this method. Ties retain the earliest session.
    /// `tracks` (by activity id) is the fallback when summary distance and laps give no result, as for a 3 km run
    /// without 1 km laps.
    public static func bestTimes(
        for distance: Distance, runs: [RunActivity], tracks: [String: RunningTrack] = [:]
    ) -> [BestTime] {
        runs.compactMap { time(for: distance, in: $0) ?? trackTime(for: distance, in: $0, track: tracks[$0.id]) }
            .sorted {
                ($0.elapsedSeconds, $0.run.startedAt, $0.run.id, $0.run.source.rawValue)
                    < ($1.elapsedSeconds, $1.run.startedAt, $1.run.id, $1.run.source.rawValue)
            }
    }

    private static let distanceRoundingMeters = 0.01
    private static let totalDistanceToleranceMeters = 1.0
    private static let timeRoundingSeconds = 0.05

    private static func time(for distance: Distance, in run: RunActivity) -> BestTime? {
        let target = Double(distance.rawValue)
        guard let elapsed = run.elapsedSeconds,
            validElapsed(elapsed, timer: run.durationSeconds),
            plausiblePace(distance: run.distanceMeters, timer: run.durationSeconds),
            (run.runWalk?.walking?.distanceMeters ?? 0) == 0,
            (run.runWalk?.walking?.durationSeconds ?? 0) == 0
        else { return nil }

        if isExactDistance(run.distanceMeters, target: target) {
            return BestTime(
                run: run, distance: distance, elapsedSeconds: elapsed, coverage: .wholeActivity,
                observedDistanceMeters: run.distanceMeters
            )
        }
        if let laps = run.laps, !laps.isEmpty,
            run.lapCount.map({ $0 == laps.count }) ?? true,
            let seconds = completeLapTimes(laps, distance: run.distanceMeters, elapsed: elapsed),
            let window = fastestWindow(laps, seconds: seconds, target: target) {
            return BestTime(
                run: run, distance: distance, elapsedSeconds: window.elapsed, coverage: .lapBoundaries,
                observedDistanceMeters: window.meters
            )
        }
        // The whole elapsed time gives an upper bound at the start-to-target crossing. Do not interpolate
        // a target split or accept a shorter activity. The 0.5% limit is a product heuristic.
        guard run.distanceMeters >= target, run.distanceMeters - target <= target * 0.005 else { return nil }
        return BestTime(
            run: run, distance: distance, elapsedSeconds: elapsed, coverage: .nearWholeActivity,
            observedDistanceMeters: run.distanceMeters
        )
    }

    private static let maximumSampleGapSeconds = 15.0

    /// Fastest continuous stretch of `distance` in the track. Windows spanning a gap in the samples (a pause)
    /// are skipped, and the start is interpolated between the two samples around it.
    private static func trackTime(for distance: Distance, in run: RunActivity, track: RunningTrack?) -> BestTime? {
        let target = Double(distance.rawValue)
        guard let track, run.distanceMeters >= target else { return nil }
        let points = track.samples.compactMap { sample -> (time: Double, meters: Double)? in
            guard let meters = sample.distanceMeters, meters.isFinite, meters >= 0 else { return nil }
            return (sample.date.timeIntervalSinceReferenceDate, meters)
        }
        let ordered = zip(points, points.dropFirst()).allSatisfy { $0.time <= $1.time && $0.meters <= $1.meters }
        guard points.count >= 2, ordered else { return nil }
        var start = 0
        var best: Double?
        for end in 1..<points.count {
            if points[end].time - points[end - 1].time > maximumSampleGapSeconds { start = end }
            while start + 1 < end, points[end].meters - points[start + 1].meters >= target { start += 1 }
            guard start < end, points[end].meters - points[start].meters >= target else { continue }
            let from = points[start]
            let next = points[start + 1]
            let wanted = points[end].meters - target
            let startTime = next.meters > from.meters
                ? from.time + (next.time - from.time) * (wanted - from.meters) / (next.meters - from.meters)
                : from.time
            let elapsed = points[end].time - startTime
            if plausiblePace(distance: target, timer: elapsed), elapsed < (best ?? .infinity) { best = elapsed }
        }
        return best.map {
            BestTime(
                run: run, distance: distance, elapsedSeconds: $0, coverage: .trackSamples,
                observedDistanceMeters: target
            )
        }
    }

    private static func isExactDistance(_ distance: Double, target: Double) -> Bool {
        abs(distance - target) <= distanceRoundingMeters
    }

    private static func completeLapTimes(_ laps: [RunLap], distance: Double, elapsed: Double) -> [Double]? {
        let seconds = laps.map { $0.elapsedSeconds ?? $0.durationSeconds }
        guard zip(laps, seconds).allSatisfy({ lap, elapsed in
            plausiblePace(distance: lap.distanceMeters, timer: lap.durationSeconds)
                && validElapsed(elapsed, timer: lap.durationSeconds)
        }),
            abs(laps.reduce(0) { $0 + $1.distanceMeters } - distance) <= totalDistanceToleranceMeters,
            abs(seconds.reduce(0, +) - elapsed) <= timeRoundingSeconds
        else { return nil }
        return seconds
    }

    private static func validElapsed(_ elapsed: Double, timer: Double) -> Bool {
        elapsed.isFinite && elapsed > 0 && elapsed >= timer - timeRoundingSeconds
    }

    private static func plausiblePace(distance: Double, timer: Double) -> Bool {
        guard distance.isFinite, distance > 0, timer.isFinite, timer > 0 else { return false }
        // Broad plausibility filter for unusable lap averages, including large distance jumps.
        return (120...2_400).contains(timer / distance * 1_000)
    }

    private static func fastestWindow(
        _ laps: [RunLap], seconds: [Double], target: Double
    ) -> (meters: Double, elapsed: Double)? {
        var start = 0
        var meters = 0.0
        var elapsed = 0.0
        var best: (meters: Double, elapsed: Double)?
        for end in laps.indices {
            meters += laps[end].distanceMeters
            elapsed += seconds[end]
            while meters > target + distanceRoundingMeters && start <= end {
                meters -= laps[start].distanceMeters
                elapsed -= seconds[start]
                start += 1
            }
            if isExactDistance(meters, target: target), elapsed < (best?.elapsed ?? .infinity) {
                best = (meters, elapsed)
            }
        }
        return best
    }
}
