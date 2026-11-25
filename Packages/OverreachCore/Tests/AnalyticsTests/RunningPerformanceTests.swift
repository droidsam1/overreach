import Analytics
import Domain
import Foundation
import Testing

@Suite
struct RunningPerformanceTests {
    @Test func picksTheFastestObservedContiguousLapWindow() {
        let laps = [
            RunLap(distanceMeters: 500, durationSeconds: 160),
            RunLap(distanceMeters: 500, durationSeconds: 155, elapsedSeconds: 185),
            RunLap(distanceMeters: 500, durationSeconds: 140),
            RunLap(distanceMeters: 500, durationSeconds: 145)
        ]
        let run = activity(distance: 2_000, timer: 600, elapsed: 630, laps: laps)
        let best = RunningPerformance.bestTimes(for: .oneKilometer, runs: [run]).first
        #expect(best?.elapsedSeconds == 285)
        #expect(best?.coverage == .lapBoundaries)
        #expect(best?.run.id == run.id)
    }

    @Test func preservesPauseTimeAndRejectsLapsWhosePauseAllocationIsUnknown() {
        let timerOnly = RunLap(distanceMeters: 1_000, durationSeconds: 320)
        let withPause = RunLap(distanceMeters: 1_000, durationSeconds: 300, elapsedSeconds: 360)
        let complete = activity(distance: 2_000, timer: 620, elapsed: 680, laps: [withPause, timerOnly])
        var incomplete = complete
        incomplete.laps?[0].elapsedSeconds = nil
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [complete]).first?.elapsedSeconds == 320)
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [incomplete]).isEmpty)
    }

    @Test func requiresAnObservedBoundaryOrExactWholeActivity() {
        let summary = activity(distance: 5_000, timer: 1_500, elapsed: 1_600)
        let exact = RunningPerformance.bestTimes(for: .fiveKilometers, runs: [summary]).first
        #expect(exact?.elapsedSeconds == 1_600)
        #expect(exact?.coverage == .wholeActivity)
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [summary]).isEmpty)
        let over = activity(
            distance: 1_010, timer: 300, elapsed: 300, laps: [RunLap(distanceMeters: 1_010, durationSeconds: 300)]
        )
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [over]).isEmpty)
        let near = activity(distance: 5_020, timer: 1_400, elapsed: 1_500)
        let bound = RunningPerformance.bestTimes(for: .fiveKilometers, runs: [near]).first
        #expect(bound?.coverage == .nearWholeActivity)
        #expect(bound?.observedDistanceMeters == 5_020)
        #expect(bound?.elapsedSeconds == 1_500)
        let short = activity(distance: 4_990, timer: 1_400, elapsed: 1_500)
        #expect(RunningPerformance.bestTimes(for: .fiveKilometers, runs: [short]).isEmpty)
        let legacy = activity(distance: 1_000, timer: 300, elapsed: nil)
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [legacy]).isEmpty)
    }

    @Test func rejectsImpossiblePaceAndIncompleteDistance() {
        let jump = RunLap(distanceMeters: 1_000, durationSeconds: 5)
        let plausible = RunLap(distanceMeters: 1_000, durationSeconds: 500)
        let implausible = activity(distance: 2_000, timer: 505, elapsed: 505, laps: [jump, plausible])
        let incomplete = activity(distance: 2_500, timer: 500, elapsed: 500, laps: [plausible])
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [implausible, incomplete]).isEmpty)
    }

    @Test func excludesKnownWalkIntervalsEvenWithoutWalkingDistance() {
        var mixed = activity(distance: 10_000, timer: 3_000, elapsed: 3_100)
        mixed.runWalk = RunWalkSplits(walking: .init(distanceMeters: 0, durationSeconds: 60, segments: 1))
        #expect(RunningPerformance.bestTimes(for: .tenKilometers, runs: [mixed]).isEmpty)
    }

    @Test func respectsCanonicalMatchingAndKeepsTiesOrdered() {
        var first = activity(id: "g", distance: 1_000, timer: 300, elapsed: 300)
        first.kind = .training
        let linkedCopy = RunActivity(
            id: "a", source: .appleHealth, startedAt: first.startedAt, durationSeconds: 300,
            distanceMeters: 1_000, elapsedSeconds: 300
        )
        var other = activity(id: "t", day: 2, distance: 1_000, timer: 300, elapsed: 300)
        other.kind = .treadmill
        let runs = RunDeduplication.resolve([other, linkedCopy, first], choices: [:]).runs.map(\.activity)
        let results = RunningPerformance.bestTimes(for: .oneKilometer, runs: runs)
        #expect(results.map(\.run.id) == ["g", "t"])
        #expect(results.map(\.kind) == [.training, .treadmill])

        let pair = RunMatchPair(garminID: "g", appleHealthID: "a")
        let separate = RunDeduplication.resolve([other, linkedCopy, first], choices: [pair: .separate])
        let kept = RunningPerformance.bestTimes(for: .oneKilometer, runs: separate.runs.map(\.activity))
        #expect(kept.count == 3)
    }

    @Test func doesNotCombineOneRecordingsElapsedTimeWithAnothersDistance() {
        let first = activity(id: "g", distance: 0, timer: 300, elapsed: 300)
        let copy = RunActivity(
            id: "a", source: .appleHealth, startedAt: first.startedAt, durationSeconds: 330,
            distanceMeters: 1_000, elapsedSeconds: 330
        )
        let canonical = RunDeduplication.resolve([first, copy], choices: [:]).runs.map(\.activity)
        #expect(canonical.first?.distanceMeters == 1_000)
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: canonical).isEmpty)
    }

    private func activity(
        id: String = "run", day: Int = 0, distance: Double, timer: Double, elapsed: Double?, laps: [RunLap]? = nil
    ) -> RunActivity {
        RunActivity(
            id: id, source: .garmin, startedAt: Date(timeIntervalSince1970: Double(day) * 86_400),
            durationSeconds: timer, distanceMeters: distance, laps: laps, elapsedSeconds: elapsed
        )
    }
}
