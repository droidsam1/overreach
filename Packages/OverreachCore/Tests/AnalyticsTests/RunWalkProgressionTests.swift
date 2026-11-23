import Analytics
import Domain
import Foundation
import Testing

@Suite("Run/walk progression")
struct RunWalkProgressionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private var now: Date { today.startDate(in: calendar).addingTimeInterval(12 * 3_600) }
    private let goal = RunningGoal(distanceMeters: 5_000, aimsForPainFree: true)

    private func run(
        daysAgo: Int, distanceKm: Double, id: String, splits: RunWalkSplits? = nil
    ) -> RunActivity {
        RunActivity(id: id, source: .garmin, startedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3_600),
                    durationSeconds: distanceKm * 400, distanceMeters: distanceKm * 1_000, runWalk: splits)
    }

    private func outcome(_ run: RunActivity, pain: Bool) -> PlannedRunCompletion {
        var completion = PlannedRunCompletion(run)
        completion.painDuring = pain
        completion.painAfter = pain
        return completion
    }

    private func advise(_ runs: [RunActivity], _ outcomes: [PlannedRunCompletion] = []) -> RunWalkProgression.Result? {
        RunWalkProgression.advise(goal: goal, runs: runs, outcomes: outcomes, now: now, calendar: calendar)
    }

    @Test func aNewRunnerStartsWithShortRunningBlocks() {
        let result = advise([])
        #expect(result?.phase == .start)
        #expect(result?.blocks == [.run(meters: 500), .walk(meters: 500), .run(meters: 500)])
    }

    @Test func withoutAWatchSplitTheNextRunStaysWithinTenPercentOfTheLongest() {
        let runs = [run(daysAgo: 7, distanceKm: 1, id: "a"), run(daysAgo: 4, distanceKm: 1.5, id: "b"),
                    run(daysAgo: 1, distanceKm: 2, id: "c")]
        let result = advise(runs, runs.map { outcome($0, pain: false) })
        #expect(result?.phase == .progress)
        #expect(result?.blocks == [.run(meters: 2_200)])
        #expect(result?.ceilingMeters == 2_200)
    }

    @Test func runsWithWalkBreaksGrowTheRunningStretchInsideTheSessionCeiling() {
        func splits(longest: Double) -> RunWalkSplits {
            RunWalkSplits(
                running: .init(distanceMeters: 2_000, durationSeconds: 700, segments: 3, longestSegmentMeters: longest),
                walking: .init(distanceMeters: 1_000, durationSeconds: 800, segments: 4)
            )
        }
        let runs = [run(daysAgo: 6, distanceKm: 2.5, id: "a", splits: splits(longest: 800)),
                    run(daysAgo: 3, distanceKm: 2.8, id: "b", splits: splits(longest: 900)),
                    run(daysAgo: 1, distanceKm: 3, id: "c", splits: splits(longest: 1_000))]
        let result = advise(runs)
        #expect(result?.phase == .progress)
        #expect(result?.usesWatchSplits == true)
        #expect(result?.continuousMeters == 1_000)
        // Longest run 3 km → at most 3.3 km in total, with the athlete's own 250 m walk breaks.
        #expect(result?.blocks == [.run(meters: 1_250), .walk(meters: 250), .run(meters: 1_250),
                                   .walk(meters: 250), .run(meters: 300)])
        #expect(result?.totalMeters == 3_300)
    }

    @Test func painAfterTheLastRunRepeatsThePainFreeSession() {
        let runs = [run(daysAgo: 4, distanceKm: 2, id: "a"), run(daysAgo: 1, distanceKm: 2.5, id: "b")]
        let result = advise(runs, [outcome(runs[0], pain: false), outcome(runs[1], pain: true)])
        #expect(result?.phase == .hold(afterGap: false))
        #expect(result?.blocks == [.run(meters: 2_000)])
    }

    @Test func painTwiceInARowStepsBack() {
        let runs = [run(daysAgo: 7, distanceKm: 2, id: "a"), run(daysAgo: 4, distanceKm: 2.5, id: "b"),
                    run(daysAgo: 1, distanceKm: 2.5, id: "c")]
        let result = advise(runs, [outcome(runs[0], pain: false), outcome(runs[1], pain: true),
                                   outcome(runs[2], pain: true)])
        #expect(result?.phase == .stepBack)
        #expect(result?.blocks == [.run(meters: 1_750)])
    }

    @Test func aThreeWeekGapHoldsInsteadOfProgressing() {
        let runs = [run(daysAgo: 21, distanceKm: 2, id: "a")]
        let result = advise(runs, [outcome(runs[0], pain: false)])
        #expect(result?.phase == .hold(afterGap: true))
        #expect(result?.blocks == [.run(meters: 2_000)])
    }

    @Test func theSessionNeverGoesPastTheGoalDistance() {
        let runs = [run(daysAgo: 1, distanceKm: 4.75, id: "a")]
        let result = advise(runs, [outcome(runs[0], pain: false)])
        #expect(result?.blocks == [.run(meters: 5_000)])
    }

    @Test func aRunThatMeetsTheGoalEndsTheProgression() {
        let runs = [run(daysAgo: 1, distanceKm: 5.2, id: "a")]
        #expect(advise(runs, [outcome(runs[0], pain: false)])?.phase == .goalReached)
        #expect(advise(runs, [outcome(runs[0], pain: true)])?.phase != .goalReached)
        #expect(RunWalkProgression.advise(goal: nil, runs: runs, outcomes: [], now: now) == nil)
    }
}
