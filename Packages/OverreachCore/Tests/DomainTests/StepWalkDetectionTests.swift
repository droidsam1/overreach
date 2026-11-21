import Domain
import Foundation
import Testing

@Suite("Walks detected from steps")
struct StepWalkDetectionTests {
    private let start = Date(timeIntervalSince1970: 1_767_862_800)  // 2026-01-08 09:00 UTC

    /// One entry per minute from `minute`, with these step counts.
    private func minutes(from minute: Int, _ counts: [Double]) -> [TimedValue] {
        counts.enumerated().map {
            TimedValue(date: start.addingTimeInterval(Double(minute + $0.offset) * 60), value: $0.element)
        }
    }

    @Test func tenWalkingMinutesInARowAreAWalk() throws {
        let walks = StepWalkDetection.walks(stepsPerMinute: minutes(from: 0, Array(repeating: 100, count: 12)))

        let walk = try #require(walks.first)
        #expect(walks.count == 1)
        #expect(walk.start == start)
        #expect(walk.durationSeconds == 12 * 60)
        #expect(walk.steps == 1_200)
        #expect(walk.source == .appleHealth)
    }

    @Test func shorterOrSlowerMovementIsNotAWalk() {
        #expect(StepWalkDetection.walks(stepsPerMinute: minutes(from: 0, Array(repeating: 100, count: 9))).isEmpty)
        #expect(StepWalkDetection.walks(stepsPerMinute: minutes(from: 0, Array(repeating: 40, count: 30))).isEmpty)
    }

    @Test func shortPausesStayInsideOneWalkAndLongerOnesSplitIt() {
        // 6 minutes, a 3-minute stop (one slow minute, two without steps), then 6 more: one walk of 15 minutes.
        let paused = minutes(from: 0, Array(repeating: 100, count: 6)) + minutes(from: 6, [20])
            + minutes(from: 9, Array(repeating: 100, count: 6))
        let walks = StepWalkDetection.walks(stepsPerMinute: paused)
        #expect(walks.count == 1)
        #expect(walks.first?.durationSeconds == Double(15 * 60))
        #expect(walks.first?.steps == 1_220)

        // A 4-minute stop splits it into two parts too short to count.
        let split = minutes(from: 0, Array(repeating: 100, count: 6))
            + minutes(from: 10, Array(repeating: 100, count: 6))
        #expect(StepWalkDetection.walks(stepsPerMinute: split).isEmpty)
    }

    @Test func slowMinutesAtTheEndAreNotPartOfTheWalk() {
        let walks = StepWalkDetection.walks(
            stepsPerMinute: minutes(from: 0, Array(repeating: 100, count: 10) + [30, 30])
        )
        #expect(walks.first?.durationSeconds == Double(10 * 60))
        #expect(walks.first?.steps == 1_000)
    }

    @Test func runningCadenceAndRecordedWorkoutsAreNotWalking() {
        let running = minutes(from: 0, Array(repeating: 165, count: 30))
        #expect(StepWalkDetection.walks(stepsPerMinute: running).isEmpty)

        // A walk that becomes a run keeps only its walking part.
        let walkThenRun = minutes(from: 0, Array(repeating: 110, count: 12) + Array(repeating: 170, count: 20))
        #expect(StepWalkDetection.walks(stepsPerMinute: walkThenRun).map(\.durationSeconds) == [Double(12 * 60)])

        // Minutes inside a recorded workout (a walking workout, a gym session) never become a detected walk.
        let workout = DateInterval(start: start.addingTimeInterval(5 * 60), duration: 20 * 60)
        let walks = StepWalkDetection.walks(
            stepsPerMinute: minutes(from: 0, Array(repeating: 100, count: 40)), excluding: [workout]
        )
        #expect(walks.map(\.start) == [start.addingTimeInterval(25 * 60)])
        #expect(walks.map(\.durationSeconds) == [Double(15 * 60)])
    }

    @Test func aWorkoutInsideAPauseSplitsTheWalk() {
        let steps = minutes(from: 0, Array(repeating: 100, count: 8))
            + minutes(from: 10, Array(repeating: 100, count: 8))
        let workout = DateInterval(start: start.addingTimeInterval(8 * 60), duration: 60)
        #expect(StepWalkDetection.walks(stepsPerMinute: steps).count == 1)
        #expect(StepWalkDetection.walks(stepsPerMinute: steps, excluding: [workout]).isEmpty)
    }

    @Test func heartRateDuringTheWalkIsAveraged() {
        let heartRate = [
            TimedValue(date: start.addingTimeInterval(-60), value: 60),
            TimedValue(date: start.addingTimeInterval(120), value: 100),
            TimedValue(date: start.addingTimeInterval(540), value: 110),
            TimedValue(date: start.addingTimeInterval(900), value: 70)
        ]
        let walks = StepWalkDetection.walks(
            stepsPerMinute: minutes(from: 0, Array(repeating: 100, count: 10)), heartRate: heartRate
        )
        #expect(walks.first?.averageHeartRate == 105)
    }
}
