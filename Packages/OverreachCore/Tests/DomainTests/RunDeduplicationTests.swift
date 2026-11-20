import Domain
import Foundation
import Testing

@Suite("Run deduplication")
struct RunDeduplicationTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func run(
        _ id: String, _ source: DataSourceKind, offsetMinutes: Double = 0, minutes: Double = 40,
        load: Double? = nil, heartRate: Double? = nil
    ) -> RunActivity {
        RunActivity(
            id: id, source: source, startedAt: start.addingTimeInterval(offsetMinutes * 60),
            durationSeconds: minutes * 60, distanceMeters: 8_000, averageHeartRate: heartRate, trainingLoad: load
        )
    }

    @Test func garminAndItsHealthCopyAreOneRunAndGarminWins() {
        let garmin = run("g1", .garmin, load: 80)
        let copy = run("h1", .appleHealth, offsetMinutes: 0.5, minutes: 39.5, heartRate: 150)

        let runs = RunDeduplication.removingDuplicates([copy, garmin])

        #expect(runs.count == 1)
        #expect(runs.first?.id == "g1")
        #expect(runs.first?.trainingLoad == 80)
        #expect(runs.first?.averageHeartRate == 150)  // filled from the copy
    }

    @Test func twoRunsTheSameDayAreBothKept() {
        let morning = run("g1", .garmin)
        let evening = run("h2", .appleHealth, offsetMinutes: 600)

        #expect(RunDeduplication.removingDuplicates([morning, evening]).map(\.id) == ["g1", "h2"])
    }

    @Test func aDoubleSessionFromOneSourceIsNeverMerged() {
        let first = run("h1", .appleHealth, minutes: 30)
        let second = run("h2", .appleHealth, offsetMinutes: 10, minutes: 30)

        #expect(RunDeduplication.removingDuplicates([first, second]).count == 2)
    }

    @Test func aSmallOverlapIsTwoRuns() {
        let first = run("g1", .garmin, minutes: 40)
        let next = run("h1", .appleHealth, offsetMinutes: 35, minutes: 40)

        #expect(RunDeduplication.removingDuplicates([first, next]).count == 2)
    }

    @Test func eachCopyIsMatchedOnce() {
        let garminA = run("gA", .garmin, minutes: 30)
        let garminB = run("gB", .garmin, offsetMinutes: 120, minutes: 30)
        let copyA = run("hA", .appleHealth, minutes: 30)
        let copyB = run("hB", .appleHealth, offsetMinutes: 120, minutes: 30)

        let runs = RunDeduplication.removingDuplicates([copyB, garminA, copyA, garminB])

        #expect(runs.map(\.id) == ["gA", "gB"])
    }
}
