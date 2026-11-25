import Domain
import Foundation

/// Descriptive comparisons of sustained running bouts from activity files.
public enum RunningBlockComparison {
    public static let calculationVersion = 1
    public static let evidence = EvidenceReference(key: "comparable-running-heart-rate", level: .limited)

    struct Location: Hashable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    public struct Result: Sendable {
        public let run: RunActivity
        public let effort: RunningBlocks.SteadyEffort
        public let sensorID: String?
        public let blockNumber: Int
        public let previousRecoverySeconds: Double?
        public let blockDurationSeconds: Double
        let route: [Location]

        public func confirmingSensor(_ identifier: String?) -> Result {
            Result(
                run: run, effort: effort, sensorID: sensorID ?? identifier,
                blockNumber: blockNumber, previousRecoverySeconds: previousRecoverySeconds,
                blockDurationSeconds: blockDurationSeconds, route: route
            )
        }

        var midpointPace: Double {
            effort.paceSecondsPerKilometer.lowerBound + span(effort.paceSecondsPerKilometer) / 2
        }

        var heartRate: Double { effort.heartRateBPM }
        var date: Date { run.startedAt }
        var sessionKey: String { "\(run.source.rawValue):\(run.id)" }
    }

    public struct Comparison: Sendable {
        public let results: [Result]
        public let summary: PerformanceComparison.Summary
        public let paceSecondsPerKilometer: ClosedRange<Double>
        public let cadenceStepsPerMinute: Double?
        public let routeMatches: Int
    }

    public static func observations(
        for run: RunActivity, track: RunningTrack, maxHeartRate: Double? = nil
    ) -> [Result] {
        guard run.kind == .training else { return [] }
        let nearMaximum = maxHeartRate.flatMap { (100...250).contains($0) ? $0 * 0.9 : nil }
        let blocks = RunningBlocks.reconstruct(from: track)
        return blocks.enumerated().compactMap { index, block in
            guard let effort = block.steady, nearMaximum.map({ effort.heartRateBPM < $0 }) ?? true else { return nil }
            let end = effort.start.addingTimeInterval(effort.durationSeconds)
            let positions = track.samples.filter { $0.date >= effort.start && $0.date <= end }
            let recovery = index > 0 ? block.start.timeIntervalSince(blocks[index - 1].end) : nil
            return Result(
                run: run, effort: effort, sensorID: track.heartRateSensorID,
                blockNumber: index + 1, previousRecoverySeconds: recovery,
                blockDurationSeconds: block.durationSeconds, route: routeSamples(positions)
            )
        }
    }

    /// Rank cohorts by coverage in both periods, then by route overlap. Measured pulse never ranks cohorts.
    public static func compare(_ results: [Result], window: PerformanceComparison) -> Comparison? {
        let eligible = results.filter {
            $0.sensorID?.isEmpty == false && window.contains($0.date)
        }
        var best: Comparison?
        for anchor in eligible {
            let cohort = cohort(anchor: anchor, eligible: eligible)
            let summary = window.summarize(cohort.results, date: \.date, value: \.heartRate)
            guard summary.currentCount > 0, summary.previousCount > 0 else { continue }
            let minimum = min(summary.previousCount, summary.currentCount)
            let priorMinimum = best.map { min($0.summary.previousCount, $0.summary.currentCount) } ?? 0
            let count = cohort.results.count
            let priorCount = best?.results.count ?? 0
            let priorRoutes = best?.routeMatches ?? 0
            guard (minimum, count, cohort.routeMatches) > (priorMinimum, priorCount, priorRoutes),
                  let pace = paceRange(cohort.results)
            else { continue }
            let cadence = cohort.results.filter { window.includes($0.date) }
                .compactMap { $0.effort.cadenceStepsPerMinute }
            best = Comparison(
                results: cohort.results, summary: summary, paceSecondsPerKilometer: pace,
                cadenceStepsPerMinute: PerformanceComparison.median(cadence), routeMatches: cohort.routeMatches
            )
        }
        return best
    }

    private static func cohort(anchor: Result, eligible: [Result]) -> (results: [Result], routeMatches: Int) {
        let candidates = eligible.filter {
            $0.sessionKey != anchor.sessionKey && comparable(anchor, $0)
        }.map { ($0, sameDirectionRoute(anchor.route, $0.route)) }
        .sorted {
            let left = preference(anchor, candidate: $0.0, route: $0.1)
            let right = preference(anchor, candidate: $1.0, route: $1.1)
            return left < right
        }
        var selected = [anchor]
        var seen = Set([anchor.sessionKey])
        var routeMatches = 0
        for (candidate, route) in candidates {
            guard !seen.contains(candidate.sessionKey), selected.allSatisfy({ comparable($0, candidate) }) else {
                continue
            }
            seen.insert(candidate.sessionKey)
            selected.append(candidate)
            if route { routeMatches += 1 }
        }
        return (selected, routeMatches)
    }

    private struct Preference: Comparable {
        let routeMismatch: Int
        let orderMismatch: Int
        let paceDifference: Double
        let durationDifference: Double
        let date: Date
        let sessionKey: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.routeMismatch, lhs.orderMismatch, lhs.paceDifference, lhs.durationDifference, lhs.date, lhs.sessionKey)
                < (rhs.routeMismatch, rhs.orderMismatch, rhs.paceDifference, rhs.durationDifference, rhs.date,
                   rhs.sessionKey)
        }
    }

    private static func preference(_ anchor: Result, candidate: Result, route: Bool) -> Preference {
        let sameOrder = anchor.blockNumber == candidate.blockNumber
        let closeRecovery = recoveryDifference(anchor, candidate).map { $0 <= 120 } ?? false
        return Preference(
            routeMismatch: route ? 0 : 1, orderMismatch: (sameOrder || closeRecovery) ? 0 : 1,
            paceDifference: abs(anchor.midpointPace - candidate.midpointPace),
            durationDifference: abs(anchor.blockDurationSeconds - candidate.blockDurationSeconds),
            date: candidate.date, sessionKey: candidate.sessionKey
        )
    }

    private static func recoveryDifference(_ lhs: Result, _ rhs: Result) -> Double? {
        guard let left = lhs.previousRecoverySeconds, let right = rhs.previousRecoverySeconds else { return nil }
        return abs(left - right)
    }

    private static func comparable(_ lhs: Result, _ rhs: Result) -> Bool {
        let leftGrade = lhs.effort.gradePercent
        let rightGrade = rhs.effort.gradePercent
        return lhs.sensorID == rhs.sensorID
            && lhs.run.source == rhs.run.source
            && abs(lhs.midpointPace - rhs.midpointPace) <= 15
            && abs(leftGrade.lowerBound - rightGrade.lowerBound) <= 1.5
            && abs(leftGrade.upperBound - rightGrade.upperBound) <= 1.5
            && abs(lhs.effort.durationSeconds - rhs.effort.durationSeconds) <= 45
    }

    private static func span(_ range: ClosedRange<Double>) -> Double {
        range.upperBound - range.lowerBound
    }

    private static func paceRange(_ results: [Result]) -> ClosedRange<Double>? {
        let paces = results.map(\.midpointPace)
        guard let low = paces.min(), let high = paces.max() else { return nil }
        return low...high
    }

    private static func routeSamples(_ samples: [RunningTrack.Sample]) -> [Location] {
        let locations = samples.compactMap { sample -> Location? in
            guard let latitude = sample.latitude, let longitude = sample.longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            return Location(latitude: latitude, longitude: longitude)
        }
        guard locations.count >= 4 else { return [] }
        return (0...8).map { locations[$0 * (locations.count - 1) / 8] }
    }

    private static func sameDirectionRoute(_ lhs: [Location], _ rhs: [Location]) -> Bool {
        guard lhs.count == 9, rhs.count == 9,
              distance(lhs[0], lhs[8]) > 75, distance(rhs[0], rhs[8]) > 75 else { return false }
        let forward = lhs.indices.dropLast().count { index in
            rhs.indices.dropLast().contains { candidate in
                distance(lhs[index], rhs[candidate]) <= 45
                    && similarDirection(lhs[index], lhs[index + 1], rhs[candidate], rhs[candidate + 1])
            }
        }
        return forward >= 5
    }

    private static func similarDirection(_ lhsStart: Location, _ lhsEnd: Location, _ rhsStart: Location,
                                         _ rhsEnd: Location) -> Bool {
        let scale = cos((lhsStart.latitude + rhsStart.latitude) * .pi / 360)
        let lhsX = (lhsEnd.longitude - lhsStart.longitude) * scale
        let lhsY = lhsEnd.latitude - lhsStart.latitude
        let rhsX = (rhsEnd.longitude - rhsStart.longitude) * scale
        let rhsY = rhsEnd.latitude - rhsStart.latitude
        let magnitude = hypot(lhsX, lhsY) * hypot(rhsX, rhsY)
        return magnitude > 0 && lhsX * rhsX + lhsY * rhsY >= magnitude * 0.7
    }

    private static func distance(_ lhs: Location, _ rhs: Location) -> Double {
        let latitude = (lhs.latitude + rhs.latitude) * .pi / 360
        return hypot((lhs.latitude - rhs.latitude) * 111_320,
                     (lhs.longitude - rhs.longitude) * 111_320 * cos(latitude))
    }
}
