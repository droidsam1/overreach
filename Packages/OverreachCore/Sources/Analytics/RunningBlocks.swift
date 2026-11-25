import Domain
import Foundation

/// Reconstructs continuous running bouts and the steady portion usable for an approximate HR comparison.
public enum RunningBlocks {
    public struct Block: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let distanceMeters: Double?
        public let steady: SteadyEffort?

        public var durationSeconds: Double { end.timeIntervalSince(start) }
    }

    public struct SteadyEffort: Equatable, Sendable {
        public let start: Date
        public let durationSeconds: Double
        public let heartRateBPM: Double
        public let heartRateCoverage: Double
        public let paceSecondsPerKilometer: ClosedRange<Double>
        public let gradePercent: ClosedRange<Double>
        public let cadenceStepsPerMinute: Double?
    }

    private struct Interval {
        let start: RunningTrack.Sample
        let end: RunningTrack.Sample

        var seconds: Double { end.date.timeIntervalSince(start.date) }
        var distance: Double? { RunningBlocks.distance(from: start, to: end) }

        var isRunning: Bool {
            let measuredSpeed = end.speedMetersPerSecond.flatMap { (0...12).contains($0) ? $0 : nil }
            guard let speed = measuredSpeed ?? distance.map({ $0 / seconds }) else { return false }
            if let cadence = end.cadenceStepsPerMinute, (1...260).contains(cadence) {
                return speed >= 1.5 && cadence >= 140
            }
            return speed >= 2.3
        }
    }

    private struct Chunk {
        let pace: Double
        let grade: Double
    }

    /// Heuristics in seconds. Skip HR settling after each running start, including the first recorded block.
    private static let pulseSettlingSeconds = 45.0
    private static let minimumSteadySeconds = 120.0
    private static let maximumSteadySeconds = 180.0
    private static let candidateStepSeconds = 15.0
    private static let minimumBlockSeconds = 90.0
    private static let sustainedWalkingSeconds = 12.0
    private static let maximumSampleGapSeconds = 10.0

    public static func reconstruct(from track: RunningTrack) -> [Block] {
        let samples = orderedSamples(track.samples)
        let splits = track.boundaries.filter { $0.kind != .automaticLap }
            .sorted { $0.date < $1.date }
        var splitIndex = splits.startIndex
        var timerRunning = splits.first { $0.kind == .timerStart || $0.kind == .timerStop }?.kind != .timerStart
        var intervals: [Interval] = []
        var blocks: [Block] = []
        var walkingSeconds = 0.0

        func flush() {
            if let result = block(intervals) { blocks.append(result) }
            intervals.removeAll(keepingCapacity: true)
            walkingSeconds = 0
        }

        for (start, end) in zip(samples, samples.dropFirst()) {
            var splitInsideInterval = false
            while splitIndex < splits.endIndex, splits[splitIndex].date < end.date {
                let split = splits[splitIndex]
                splitInsideInterval = splitInsideInterval || split.date > start.date
                flush()
                if split.kind == .timerStop { timerRunning = false }
                if split.kind == .timerStart { timerRunning = true }
                splitIndex += 1
            }
            guard timerRunning, !splitInsideInterval else { continue }
            let interval = Interval(start: start, end: end)
            guard interval.seconds <= maximumSampleGapSeconds else {
                flush()
                continue
            }
            if interval.isRunning {
                walkingSeconds = 0
                intervals.append(interval)
            } else if !intervals.isEmpty {
                walkingSeconds += interval.seconds
                if walkingSeconds >= sustainedWalkingSeconds { flush() }
            }
        }
        flush()
        return blocks
    }

    private static func orderedSamples(_ samples: [RunningTrack.Sample]) -> [RunningTrack.Sample] {
        let sorted = samples.filter { $0.date.timeIntervalSinceReferenceDate.isFinite }.sorted { $0.date < $1.date }
        var dates: Set<Date> = []
        return sorted.filter { dates.insert($0.date).inserted }
    }

    private static func block(_ intervals: [Interval]) -> Block? {
        guard let first = intervals.first, let last = intervals.last else { return nil }
        let duration = last.end.date.timeIntervalSince(first.start.date)
        guard duration >= minimumBlockSeconds else { return nil }
        return Block(
            start: first.start.date,
            end: last.end.date,
            distanceMeters: distance(from: first.start, to: last.end),
            steady: steadyEffort(intervals, blockStart: first.start.date)
        )
    }

    private static func steadyEffort(_ intervals: [Interval], blockStart: Date) -> SteadyEffort? {
        let settled = intervals.drop(while: { $0.start.date.timeIntervalSince(blockStart) < pulseSettlingSeconds })
        var best: SteadyEffort?
        var nextStart = blockStart
        for index in settled.indices {
            let start = settled[index].start.date
            guard start >= nextStart else { continue }
            nextStart = start.addingTimeInterval(candidateStepSeconds)
            let remainder = settled[index...]
            for target in [maximumSteadySeconds, minimumSteadySeconds] {
                let sample = remainder.prefix { $0.end.date.timeIntervalSince(start) <= target }
                if let effort = measure(sample), effort.durationSeconds > (best?.durationSeconds ?? 0) {
                    best = effort
                }
            }
        }
        return best
    }

    private static func measure(_ steady: ArraySlice<Interval>) -> SteadyEffort? {
        guard let first = steady.first, let last = steady.last else { return nil }
        let duration = last.end.date.timeIntervalSince(first.start.date)
        guard duration >= minimumSteadySeconds,
              steady.reduce(0, { $0 + $1.seconds }) >= duration * 0.95,
              let chunks = chunks(in: steady),
              let pace = range(chunks.map(\.pace)), pace.upperBound - pace.lowerBound <= 30,
              let grade = range(chunks.map(\.grade)), grade.upperBound - grade.lowerBound <= 4
        else { return nil }
        let readings = steady.compactMap { interval -> (value: Double, seconds: Double)? in
            guard let value = interval.end.heartRateBPM, (35...230).contains(value) else { return nil }
            return (value, interval.seconds)
        }
        let covered = readings.reduce(0) { $0 + $1.seconds }
        guard covered >= duration * 0.9, let bpm = weightedMedian(readings) else { return nil }
        let cadence = steady.compactMap { interval -> (value: Double, seconds: Double)? in
            guard let value = interval.end.cadenceStepsPerMinute, (1...260).contains(value) else { return nil }
            return (value, interval.seconds)
        }
        return SteadyEffort(
            start: first.start.date, durationSeconds: duration, heartRateBPM: bpm,
            heartRateCoverage: covered / duration, paceSecondsPerKilometer: pace, gradePercent: grade,
            cadenceStepsPerMinute: weightedMedian(cadence)
        )
    }

    /// Work in approximately minute-long bins for pace and slope, folding any short tail into the last bin.
    private static func chunks(in intervals: ArraySlice<Interval>) -> [Chunk]? {
        guard let first = intervals.first, let last = intervals.last else { return nil }
        var from = first.start
        var result: [Chunk] = []
        for interval in intervals {
            let seconds = interval.end.date.timeIntervalSince(from.date)
            let remainingSeconds = last.end.date.timeIntervalSince(interval.end.date)
            let endsChunk = seconds >= 60 && remainingSeconds >= 45
            guard interval.end.date == last.end.date || endsChunk else { continue }
            guard let length = distance(from: from, to: interval.end), length > 0,
                  let fromAltitude = from.altitudeMeters, let toAltitude = interval.end.altitudeMeters else {
                return nil
            }
            let pace = seconds / length * 1_000
            let grade = (toAltitude - fromAltitude) / length * 100
            guard (120...900).contains(pace), (-15...15).contains(grade) else { return nil }
            result.append(Chunk(pace: pace, grade: grade))
            from = interval.end
        }
        return result
    }

    private static func distance(from start: RunningTrack.Sample, to end: RunningTrack.Sample) -> Double? {
        guard let first = start.distanceMeters, let last = end.distanceMeters else { return nil }
        let difference = last - first
        return difference.isFinite && difference >= 0 ? difference : nil
    }

    private static func range(_ values: [Double]) -> ClosedRange<Double>? {
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        return minimum...maximum
    }

    private static func weightedMedian(_ values: [(value: Double, seconds: Double)]) -> Double? {
        let midpoint = values.reduce(0, { $0 + $1.seconds }) / 2
        var elapsed = 0.0
        for entry in values.sorted(by: { $0.value < $1.value }) {
            elapsed += entry.seconds
            if elapsed >= midpoint { return entry.value }
        }
        return nil
    }
}
