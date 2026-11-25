import Analytics
import Domain
import Foundation
import Testing

@Suite("Garmin run and walk blocks")
struct RunningBlocksTests {
    private let origin = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func firstBlockCountsAndAutomaticLapsDoNotSplitIt() throws {
        let track = RunningTrack(
            samples: samples(seconds: 0...660, walking: [240...419]),
            boundaries: [
                boundary(0, .timerStart), boundary(180, .automaticLap), boundary(240, .manualLap),
                boundary(420, .manualLap), boundary(600, .automaticLap), boundary(660, .timerStop)
            ]
        )
        let blocks = RunningBlocks.reconstruct(from: track)
        #expect(blocks.count == 2)
        let first = try #require(blocks.first)
        #expect(first.start == origin)
        #expect(first.durationSeconds == 239)
        #expect((790...805).contains(first.distanceMeters ?? 0))
        let steady = try #require(first.steady)
        #expect(steady.start.timeIntervalSince(origin) == 45)
        #expect(steady.heartRateBPM == 145)
        #expect(steady.cadenceStepsPerMinute == 170)
        #expect(abs(steady.paceSecondsPerKilometer.lowerBound - 300) < 0.001)
        #expect(abs(steady.gradePercent.lowerBound - 1) < 0.001)
        let second = try #require(blocks.last)
        #expect(second.start.timeIntervalSince(origin) == 420)
        #expect(second.durationSeconds == 240)
    }

    @Test func detectsAnUnmarkedWalkAndExcludesPauseTime() {
        let track = RunningTrack(
            samples: samples(seconds: 0...900, walking: [210...389]),
            boundaries: [boundary(630, .timerStop), boundary(720, .timerStart)]
        )
        let blocks = RunningBlocks.reconstruct(from: track)
        #expect(blocks.map { $0.durationSeconds } == [209, 241, 180])
        #expect(blocks.map { $0.start.timeIntervalSince(origin) } == [0, 389, 720])
    }

    @Test func aShortOrSparseBlockRemainsVisibleWithoutAComparableEffort() {
        let short = RunningTrack(samples: samples(seconds: 0...140))
        let sparse = RunningTrack(samples: samples(seconds: 0...200, heartRate: { _ in nil }))
        #expect(RunningBlocks.reconstruct(from: short).first?.steady == nil)
        #expect(RunningBlocks.reconstruct(from: sparse).first?.steady == nil)
        #expect(RunningBlocks.reconstruct(from: short).count == 1)
        #expect(RunningBlocks.reconstruct(from: sparse).count == 1)
    }

    @Test func findsASteadyPortionWithinAVariableBlock() throws {
        let track = RunningTrack(samples: samples(
            seconds: 0...400, runningSpeed: { $0 <= 120 ? 2.5 : 10.0 / 3 }
        ))
        let block = try #require(RunningBlocks.reconstruct(from: track).first)
        #expect(block.durationSeconds == 400)
        let effort = try #require(block.steady)
        #expect(effort.start.timeIntervalSince(origin) > 45)
        #expect(effort.durationSeconds == 180)
        #expect(effort.paceSecondsPerKilometer.upperBound < 330)
    }

    @Test func reorderedAndIrregularSamplesUseActualElapsedTime() throws {
        let readings = samples(seconds: 0...210).enumerated()
            .compactMap { $0.offset % 3 == 0 ? $0.element : nil }
        let track = RunningTrack(samples: readings.reversed() + [readings[4]])
        let effort = try #require(RunningBlocks.reconstruct(from: track).first?.steady)
        #expect(effort.durationSeconds == 165)
        #expect(effort.heartRateCoverage == 1)
        #expect(effort.heartRateBPM == 145)
    }

    private func boundary(_ seconds: Int, _ kind: RunningTrack.BoundaryKind) -> RunningTrack.Boundary {
        RunningTrack.Boundary(date: origin.addingTimeInterval(Double(seconds)), kind: kind)
    }

    private func samples(
        seconds: ClosedRange<Int>, walking: [ClosedRange<Int>] = [],
        heartRate: (Int) -> Double? = { $0 < 45 ? 100 : 145 },
        runningSpeed: (Int) -> Double = { _ in 10.0 / 3 }
    ) -> [RunningTrack.Sample] {
        var distance = 0.0
        return seconds.map { time in
            let walks = walking.contains { $0.contains(time) }
            let speed = walks ? 1.1 : runningSpeed(time)
            if time > seconds.lowerBound { distance += speed }
            return RunningTrack.Sample(
                date: origin.addingTimeInterval(Double(time)), distanceMeters: distance,
                speedMetersPerSecond: speed, altitudeMeters: distance * 0.01,
                heartRateBPM: heartRate(time), cadenceStepsPerMinute: walks ? 90 : 170
            )
        }
    }
}
