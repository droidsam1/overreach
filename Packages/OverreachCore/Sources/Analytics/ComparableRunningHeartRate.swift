import Domain
import Foundation

public enum ComparableRunningHeartRate {
    public static let calculationVersion = 1
    public static let evidence = EvidenceReference(key: "comparable-running-heart-rate", level: .limited)

    /// Candidate from an ordered stream or a controlled test. Workout summary averages alone cannot describe
    /// a steady submaximal segment, its sensor, or its conditions.
    public struct Segment: Equatable, Sendable {
        public let run: RunActivity
        public let offsetSeconds: Double
        public let durationSeconds: Double
        public let paceSecondsPerKilometer: ClosedRange<Double>
        public let gradePercent: ClosedRange<Double>
        public let heartRateBPM: Double
        public let heartRateCoverage: Double
        public let cadenceStepsPerMinute: Double?
        public let sensorID: String
        public let conditionsID: String
        public let isSubmaximal: Bool
        public let hasPauses: Bool

        public init(
            run: RunActivity, offsetSeconds: Double, durationSeconds: Double,
            paceSecondsPerKilometer: ClosedRange<Double>, gradePercent: ClosedRange<Double>,
            heartRateBPM: Double, heartRateCoverage: Double, cadenceStepsPerMinute: Double? = nil,
            sensorID: String, conditionsID: String, isSubmaximal: Bool, hasPauses: Bool
        ) {
            self.run = run
            self.offsetSeconds = offsetSeconds
            self.durationSeconds = durationSeconds
            self.paceSecondsPerKilometer = paceSecondsPerKilometer
            self.gradePercent = gradePercent
            self.heartRateBPM = heartRateBPM
            self.heartRateCoverage = heartRateCoverage
            self.cadenceStepsPerMinute = cadenceStepsPerMinute
            self.sensorID = sensorID
            self.conditionsID = conditionsID
            self.isSubmaximal = isSubmaximal
            self.hasPauses = hasPauses
        }
    }

    public struct Comparison: Equatable, Sendable {
        public let paceSecondsPerKilometer: ClosedRange<Double>
        public let summary: PerformanceComparison.Summary
        public let segments: [Segment]
        public let cadenceStepsPerMinute: Double?
    }

    private struct Stratum: Hashable {
        let paceBand: Int
        let gradeBand: Int
        let durationBand: Int
        let kind: RunActivity.Kind
        let source: DataSourceKind
        let sensorID: String
        let conditionsID: String

        var pace: ClosedRange<Double> { Double(paceBand * 15)...Double((paceBand + 1) * 15) }
    }

    private struct Observation {
        let segment: Segment
        let stratum: Stratum
        var date: Date { segment.run.startedAt }
        var heartRate: Double { segment.heartRateBPM }
    }

    private struct Session: Hashable {
        let source: DataSourceKind
        let id: String
    }

    /// Compares medians in equal calendar windows using at most one qualifying segment per canonical activity.
    /// Returns nil unless both periods supply three sessions in a common set of conditions.
    public static func compare(segments: [Segment], window: PerformanceComparison) -> Comparison? {
        let eligible = segments.compactMap(observation).sorted(by: earlier)
        let strata = Dictionary(grouping: eligible, by: \.stratum)
        var compared: Set<Stratum> = []
        return eligible.lazy
            .filter { compared.insert($0.stratum).inserted }
            .compactMap { comparison(strata[$0.stratum, default: []], window: window) }
            .max(by: weaker)
    }

    private static func observation(_ segment: Segment) -> Observation? {
        guard let elapsed = segment.run.elapsedSeconds,
            elapsed.isFinite, segment.offsetSeconds.isFinite, segment.offsetSeconds >= 600,
            (240..<900).contains(segment.durationSeconds), segment.offsetSeconds + segment.durationSeconds <= elapsed,
            segment.isSubmaximal, !segment.hasPauses, (0.9...1).contains(segment.heartRateCoverage),
            (35...230).contains(segment.heartRateBPM), !segment.sensorID.isEmpty, !segment.conditionsID.isEmpty,
            let pace = band(segment.paceSecondsPerKilometer, within: 120...1_200, width: 15),
            let grade = band(segment.gradePercent, within: -10...10, width: 2),
            let kind = segment.run.kind, kind == .training || kind == .treadmill
        else { return nil }
        return Observation(
            segment: segment,
            stratum: Stratum(
                paceBand: pace, gradeBand: grade, durationBand: Int(segment.durationSeconds / 60),
                kind: kind, source: segment.run.source, sensorID: segment.sensorID, conditionsID: segment.conditionsID
            )
        )
    }

    private static func band(_ values: ClosedRange<Double>, within limits: ClosedRange<Double>, width: Double) -> Int? {
        guard limits.contains(values.lowerBound), limits.contains(values.upperBound) else { return nil }
        let lower = (values.lowerBound / width).rounded(.down)
        guard values.upperBound <= (lower + 1) * width else { return nil }
        return Int(lower)
    }

    private static func earlier(_ lhs: Observation, _ rhs: Observation) -> Bool {
        let left = lhs.segment
        let right = rhs.segment
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return (left.run.source.rawValue, left.run.id, left.offsetSeconds, left.durationSeconds)
            < (right.run.source.rawValue, right.run.id, right.offsetSeconds, right.durationSeconds)
    }

    private static func comparison(_ observations: [Observation], window: PerformanceComparison) -> Comparison? {
        guard let stratum = observations.first?.stratum else { return nil }
        var seen: Set<Session> = []
        let onePerSession = observations.filter {
            seen.insert(Session(source: $0.segment.run.source, id: $0.segment.run.id)).inserted
        }
        let summary = window.summarize(onePerSession, date: \.date, value: \.heartRate)
        guard min(summary.currentCount, summary.previousCount) >= 3 else { return nil }
        let cadence = onePerSession.lazy.filter { window.includes($0.date) }
            .compactMap { $0.segment.cadenceStepsPerMinute }
            .filter { $0.isFinite && $0 > 0 }
        return Comparison(
            paceSecondsPerKilometer: stratum.pace, summary: summary, segments: onePerSession.map(\.segment),
            cadenceStepsPerMinute: PerformanceComparison.median(Array(cadence))
        )
    }

    private static func weaker(_ left: Comparison, _ right: Comparison) -> Bool {
        let leftSamples = min(left.summary.currentCount, left.summary.previousCount)
        let rightSamples = min(right.summary.currentCount, right.summary.previousCount)
        if leftSamples != rightSamples { return leftSamples < rightSamples }
        if left.summary.currentCount != right.summary.currentCount {
            return left.summary.currentCount < right.summary.currentCount
        }
        guard let leftFirst = left.segments.first, let rightFirst = right.segments.first else { return false }
        return (leftFirst.run.startedAt, leftFirst.run.source.rawValue, leftFirst.run.id)
            < (rightFirst.run.startedAt, rightFirst.run.source.rawValue, rightFirst.run.id)
    }
}
