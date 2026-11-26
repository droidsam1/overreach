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

    @Test func fallsBackToTheFastestKilometreOfTheTrack() {
        // 3 km at 5:00/km for the first 2 km, then 4:00/km; one sample per 10 s.
        var samples: [RunningTrack.Sample] = []
        var meters = 0.0
        for second in stride(from: 0, through: 1_000, by: 10) {
            samples.append(.init(date: Date(timeIntervalSince1970: Double(second)), distanceMeters: meters))
            meters += (meters < 2_000 ? 10.0 / 300 : 10.0 / 240) * 1_000
        }
        let run = activity(distance: 3_000, timer: 1_000, elapsed: 1_000)
        let track = RunningTrack(samples: samples)
        let best = RunningPerformance.bestTimes(for: .oneKilometer, runs: [run], tracks: ["run": track]).first
        #expect(best?.coverage == .trackSamples)
        #expect(abs((best?.elapsedSeconds ?? 0) - 240) < 1)
        #expect(RunningPerformance.bestTimes(for: .oneKilometer, runs: [run]).isEmpty)
        let paused = RunningTrack(samples: samples.enumerated().map { index, sample in
            .init(date: sample.date.addingTimeInterval(index >= 50 ? 60 : 0), distanceMeters: sample.distanceMeters)
        })
        let withPause = RunningPerformance.bestTimes(for: .oneKilometer, runs: [run], tracks: ["run": paused]).first
        #expect((withPause?.elapsedSeconds ?? 0) >= 240)
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
