import AIExchange
import Domain
import Foundation
import Testing

@Suite("AI context pack: run/walk split")
struct ContextPackRunWalkTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func runsJSON(_ runs: [RunActivity]) throws -> NSArray {
        let today = CalendarDay(now, calendar: calendar)
        let pack = ContextPackBuilder.build(
            ContextInput(runs: runs), period: today.adding(days: -27, calendar: calendar)...today, now: now,
            calendar: calendar
        )
        let object = try #require(JSONSerialization.jsonObject(with: ContextMessage.json(pack)) as? [String: Any])
        return try #require(object["runs"] as? NSArray)
    }

    @Test func exportsTheWatchSplitLapsAndRunningPace() throws {
        let run = RunActivity(
            id: "g1", source: .garmin, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 2_400.4,
            distanceMeters: 4_800.2, lapCount: 5, movingDurationSeconds: 2_300.6,
            runWalk: RunWalkSplits(
                running: .init(distanceMeters: 3_600, durationSeconds: 1_440, segments: 4,
                               longestSegmentMeters: 1_210.4, averageCadence: 168.4),
                walking: .init(distanceMeters: 1_200, durationSeconds: 900, segments: 3, longestSegmentMeters: 450),
                standing: .init(distanceMeters: 0, durationSeconds: 60, segments: 1)
            )
        )
        // Fixture: the `runs` entry an assistant reads, with the optional fields added after v1 shipped.
        let fixture = """
            [{"date":"2026-09-20","distanceMeters":4800,"durationSeconds":2400,"lapCount":5,\
            "longestContinuousRunMeters":1210,"movingDurationSeconds":2301,"paceSecondsPerKm":500,\
            "runWalk":{"running":{"averageCadence":168,"distanceMeters":3600,"durationSeconds":1440,\
            "longestSegmentMeters":1210,"segments":4},"standing":{"distanceMeters":0,"durationSeconds":60,\
            "segments":1},"walking":{"distanceMeters":1200,"durationSeconds":900,"longestSegmentMeters":450,\
            "segments":3}},"runningPaceSecondsPerKm":400,"source":"garmin","startedAt":"2026-09-20T14:13:20Z"}]
            """
        let expected = try #require(
            JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? NSArray
        )
        #expect(try runsJSON([run]) == expected)
    }

    @Test func leavesTheNewFieldsOutWhenTheSourceHasNoSplit() throws {
        let run = RunActivity(
            id: "h1", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let json = try #require(try runsJSON([run]).firstObject as? [String: Any])
        for key in ["runWalk", "lapCount", "movingDurationSeconds", "runningPaceSecondsPerKm",
                    "longestContinuousRunMeters"] {
            #expect(json[key] == nil)
        }
    }

    @Test func readsAPackWithoutTheNewFields() throws {
        let run = RunActivity(
            id: "h1", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800,
            distanceMeters: 5_000
        )
        let today = CalendarDay(now, calendar: calendar)
        let pack = ContextPackBuilder.build(
            ContextInput(runs: [run]), period: today.adding(days: -27, calendar: calendar)...today, now: now,
            calendar: calendar
        )
        let decoded = try ContextMessage.decode(ContextMessage.json(pack))
        #expect(decoded.version == 1)
        #expect(decoded.runs.first?.runWalk == nil)
    }
}
