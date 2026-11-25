import Analytics
import Domain
import Foundation
import Testing

@Suite
struct ComparableRunningHeartRateTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func comparesMediansWithOneObservationPerSession() throws {
        let sessions = samples() + [segment(day: 5, bpm: 150, offset: 800)]
        let result = try #require(ComparableRunningHeartRate.compare(segments: sessions, window: window))
        #expect(result.summary.previousCount == 3)
        #expect(result.summary.currentCount == 3)
        #expect(result.summary.delta == -7)
        #expect(result.paceSecondsPerKilometer == 330...345)
        #expect(result.cadenceStepsPerMinute == 172)
    }

    @Test(arguments: ["sensor", "weather", "terrain", "intervals", "pause", "coverage", "warmup"])
    func requiresComparableConditionsAndThreeSessionsOnEachSide(change: String) {
        let altered = segment(
            day: 7, bpm: 140, sensor: change == "sensor" ? "wrist" : "strap",
            conditions: change == "weather" ? "hot" : "mild",
            grade: change == "terrain" ? 3...4 : 0...1,
            pace: change == "intervals" ? 270...420 : 333...341,
            pauses: change == "pause", coverage: change == "coverage" ? 0.7 : 0.95,
            offset: change == "warmup" ? 300 : 660
        )
        #expect(ComparableRunningHeartRate.compare(segments: samples().dropLast() + [altered], window: window) == nil)
    }

    private var window: PerformanceComparison {
        PerformanceComparison(through: day(7), days: 4, calendar: calendar)
    }

    private func day(_ offset: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: 1, day: offset + 1)
    }

    private func samples() -> [ComparableRunningHeartRate.Segment] {
        [segment(day: 1, bpm: 150), segment(day: 2, bpm: 149), segment(day: 3, bpm: 147),
         segment(day: 5, bpm: 142), segment(day: 6, bpm: 144), segment(day: 7, bpm: 141)]
    }

    private func segment(
        day offsetDay: Int, bpm: Double, sensor: String = "strap", conditions: String = "mild",
        grade: ClosedRange<Double> = 0...1, pace: ClosedRange<Double> = 333...341,
        pauses: Bool = false, coverage: Double = 0.95, offset: Double = 660
    ) -> ComparableRunningHeartRate.Segment {
        let run = RunActivity(
            id: "run-\(offsetDay)", source: .garmin, startedAt: day(offsetDay).startDate(in: calendar),
            durationSeconds: 1_400, distanceMeters: 4_000, elapsedSeconds: 1_400, kind: .training
        )
        return ComparableRunningHeartRate.Segment(
            run: run, offsetSeconds: offset, durationSeconds: 300, paceSecondsPerKilometer: pace,
            gradePercent: grade, heartRateBPM: bpm, heartRateCoverage: coverage, cadenceStepsPerMinute: 172,
            sensorID: sensor, conditionsID: conditions, isSubmaximal: true, hasPauses: pauses
        )
    }
}
