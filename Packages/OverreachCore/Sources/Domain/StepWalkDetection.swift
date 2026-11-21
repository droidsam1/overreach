import Foundation

/// Walks found in minute-by-minute step counts when nothing recorded them as a workout (ADR-0010,
/// `docs/design/daily-activity.md`, defaults in `walking-load-baseline`). The dog's walks and the commute are the
/// walks a person rarely starts on the watch, so without this they never reach the usual day.
public enum StepWalkDetection {
    public struct Settings: Hashable, Sendable {
        /// Shortest walk, from the first to the last walking minute.
        public var minimumMinutes: Int
        /// A minute with at least this many steps is a walking minute.
        public var minimumStepsPerMinute: Double
        /// A minute with more steps than this is running, not walking (walk-to-run transition ≈ 140 steps/min).
        public var maximumStepsPerMinute: Double
        /// Pauses up to this long (a crossing, a lead to untangle) stay inside one walk.
        public var maximumGapMinutes: Int

        public init(
            minimumMinutes: Int = 10, minimumStepsPerMinute: Double = 60, maximumStepsPerMinute: Double = 140,
            maximumGapMinutes: Int = 3
        ) {
            self.minimumMinutes = minimumMinutes
            self.minimumStepsPerMinute = minimumStepsPerMinute
            self.maximumStepsPerMinute = maximumStepsPerMinute
            self.maximumGapMinutes = maximumGapMinutes
        }
    }

    /// - Parameters:
    ///   - stepsPerMinute: step counts of one-minute intervals, each dated at the start of its minute.
    ///   - workouts: recorded workouts of any kind. Their minutes never become walks: a walking workout is a walk
    ///     already, and steps inside a run or a gym session are not walking.
    ///   - heartRate: heart-rate samples; the average of those inside a walk is attached to it.
    ///   - source: where the step counts came from.
    public static func walks(
        stepsPerMinute: [TimedValue], excluding workouts: [DateInterval] = [], heartRate: [TimedValue] = [],
        source: DataSourceKind = .appleHealth, settings: Settings = Settings()
    ) -> [WalkBout] {
        let workouts = workouts.sorted { $0.start < $1.start }
        let heartRate = heartRate.sorted { $0.date < $1.date }
        let maximumGap = Double(settings.maximumGapMinutes + 1) * 60
        var walks: [WalkBout] = []
        var current: OpenWalk?

        func close() {
            defer { current = nil }
            guard let walk = current else { return }
            let end = walk.last.addingTimeInterval(60)
            guard end.timeIntervalSince(walk.start) >= Double(settings.minimumMinutes) * 60 else { return }
            walks.append(WalkBout(
                start: walk.start,
                durationSeconds: end.timeIntervalSince(walk.start),
                steps: Int(walk.stepsAtLast.rounded()),
                averageHeartRate: averageHeartRate(heartRate, from: walk.start, until: end),
                source: source
            ))
        }

        for minute in stepsPerMinute.sorted(by: { $0.date < $1.date }) {
            if let walk = current, minute.date.timeIntervalSince(walk.last) > maximumGap
                || workouts.contains(where: { $0.overlaps(from: walk.last, until: minute.date) }) {
                close()
            }
            let isWalking = minute.value >= settings.minimumStepsPerMinute
            if workouts.contains(where: { $0.overlaps(from: minute.date, until: minute.date.addingTimeInterval(60)) })
                || minute.value > settings.maximumStepsPerMinute {
                close()
            } else if var walk = current {
                walk.steps += minute.value
                if isWalking {
                    walk.last = minute.date
                    walk.stepsAtLast = walk.steps
                }
                current = walk
            } else if isWalking {
                current = OpenWalk(
                    start: minute.date, last: minute.date, steps: minute.value, stepsAtLast: minute.value
                )
            }
        }
        close()
        return walks
    }

    /// The walk being built: its first minute, its last walking minute, all steps so far and those up to that minute.
    private struct OpenWalk {
        var start: Date
        var last: Date
        var steps: Double
        var stepsAtLast: Double
    }

    private static func averageHeartRate(_ samples: [TimedValue], from start: Date, until end: Date) -> Double? {
        var low = 0
        var high = samples.count
        while low < high {
            let middle = (low + high) / 2
            if samples[middle].date < start { low = middle + 1 } else { high = middle }
        }
        let beats = samples[low...].prefix { $0.date < end }.map(\.value)
        return beats.isEmpty ? nil : beats.reduce(0, +) / Double(beats.count)
    }
}

private extension DateInterval {
    /// Whether `[from, until)` overlaps this interval.
    func overlaps(from: Date, until: Date) -> Bool {
        start < until && from < end
    }
}
