import Analytics
import Domain
import Foundation
import Testing

@Suite("Comparable Garmin running blocks")
struct RunningBlockComparisonTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 25)

    @Test func acceptsTwoDistinctRoutesAndOnlyCountsOneBlockPerSession() throws {
        let earlier = run("earlier", day: -31, pulse: 149)
        let later = run("recent", day: -2, pulse: 143, longitude: 0.05)
        let result = try #require(RunningBlockComparison.compare(earlier + later + later, window: window))
        #expect(result.results.count == 2)
        #expect(result.summary.delta == -6)
        #expect(result.cadenceStepsPerMinute == 170)
        #expect(result.routeMatches == 0)
    }

    @Test func prefersSameDirectionWhenChoosingBetweenComparableBlocks() throws {
        let earlier = run("earlier", day: -31, pulse: 149)
        let recent = run("recent", day: -2, pulse: 143)
        let reversed = run("recent", day: -2, pulse: 145, reversed: true)
        let result = try #require(RunningBlockComparison.compare(earlier + reversed + recent, window: window))
        #expect(result.results.count == 2)
        #expect(result.routeMatches == 1)
        #expect(result.summary.delta == -6)
    }

    @Test func rejectsSensorChangesTimingAndSteepness() {
        let baseline = run("earlier", day: -31, pulse: 149)
        #expect(compare(baseline + run("other", day: -2, pulse: 145, sensor: "strap")) == nil)
        #expect(compare(baseline + run("other", day: -2, pulse: 145, grade: 4)) == nil)
        #expect(compare(baseline + run("other", day: -2, pulse: 145, speed: 4)) == nil)
        #expect(compare(baseline + run("other", day: -2, pulse: 145, duration: 600)) == nil)
    }

    @Test func requiresConfirmationWhenTheSensorIsUnknown() {
        let earlier = run("earlier", day: -31, pulse: 149, sensor: nil)
        let recent = run("recent", day: -2, pulse: 145, sensor: nil)
        #expect(compare(earlier + recent) == nil)
        #expect(compare((earlier + recent).map { $0.confirmingSensor("known") })?.summary.delta == -4)
        let measuredSensor = run("measured", day: -2, pulse: 145)
        #expect(measuredSensor.first?.confirmingSensor("strap").sensorID == "watch")
    }

    private var window: PerformanceComparison {
        PerformanceComparison(through: today, days: 30, calendar: calendar)
    }

    private func compare(_ results: [RunningBlockComparison.Result]) -> RunningBlockComparison.Comparison? {
        RunningBlockComparison.compare(results, window: window)
    }

    private func run(
        _ id: String, day: Int, pulse: Double, sensor: String? = "watch", longitude: Double = 0,
        reversed: Bool = false, duration: Int = 260, grade: Double = 1, speed: Double = 10.0 / 3
    ) -> [RunningBlockComparison.Result] {
        let date = today.adding(days: day, calendar: calendar).startDate(in: calendar)
        let run = RunActivity(
            id: id, source: .garmin, startedAt: date, durationSeconds: Double(duration),
            distanceMeters: Double(duration) * speed, kind: .training
        )
        let points = (0...duration).map { elapsed in
            let meters = speed * Double(elapsed)
            return RunningTrack.Sample(
                date: date.addingTimeInterval(Double(elapsed)), distanceMeters: meters,
                speedMetersPerSecond: speed, altitudeMeters: meters * grade / 100, heartRateBPM: pulse,
                cadenceStepsPerMinute: 170, latitude: 40 + Double(reversed ? duration - elapsed : elapsed) * 0.00003,
                longitude: longitude
            )
        }
        return RunningBlockComparison.observations(
            for: run, track: RunningTrack(samples: points, heartRateSensorID: sensor)
        )
    }
}
