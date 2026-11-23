import Analytics
import Domain
import Foundation
import Testing

@Suite("Single-session ceiling for dated runs")
struct SessionCeilingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()
    private let today = CalendarDay(year: 2026, month: 11, day: 20)

    private func run(daysAgo: Int, km: Double, minutes: Double = 50, hour: Double = 8, id: String? = nil) -> RunActivity {
        let start = today.adding(days: -daysAgo, calendar: calendar).startDate(in: calendar)
            .addingTimeInterval(hour * 3_600)
        return RunActivity(id: id ?? "\(daysAgo)-\(hour)", source: .garmin, startedAt: start,
                           durationSeconds: minutes * 60, distanceMeters: km * 1_000)
    }

    private func planned(inDays days: Int, km: Int? = nil, minutes: Int? = nil,
                         purpose: PlannedRun.Purpose = .long) -> PlannedRun {
        PlannedRun(day: today.adding(days: days, calendar: calendar), purpose: purpose, durationMinutes: minutes,
                   distanceMeters: km.map { $0 * 1_000 })
    }

    private func warnings(_ schedule: [PlannedRun], runs: [RunActivity]) -> [UUID: SessionCeiling.Warning] {
        SessionCeiling.warnings(schedule: schedule, runs: runs, today: today, calendar: calendar)
    }

    @Test func aLongRunWithinTheCeilingPassesAndOneOverItIsFlagged() throws {
        let runs = [run(daysAgo: 5, km: 10), run(daysAgo: 40, km: 20)]
        let within = planned(inDays: 2, km: 11)
        let over = planned(inDays: 2, km: 13)

        #expect(warnings([within], runs: runs).isEmpty)
        let warning = try #require(warnings([over], runs: runs)[over.id])
        #expect(warning.longestMeters == 10_000)
        #expect(warning.plannedMeters == 13_000)
        #expect(warning.ceilingMeters == 11_000)
        #expect(!warning.isEstimated)
    }

    @Test func withoutHistoryThereIsNoCeiling() {
        #expect(warnings([planned(inDays: 1, km: 30)], runs: []).isEmpty)
        #expect(warnings([planned(inDays: 1, km: 30)], runs: [run(daysAgo: 31, km: 5)]).isEmpty)
    }

    @Test func twoRunsTenMinutesApartCountAsOneSession() {
        let first = run(daysAgo: 3, km: 5, minutes: 25, hour: 8, id: "a")
        let second = run(daysAgo: 3, km: 5, minutes: 25, hour: 8 + 35.0 / 60, id: "b")
        let apart = run(daysAgo: 3, km: 5, minutes: 25, hour: 18, id: "c")
        let long = planned(inDays: 1, km: 10)

        #expect(SessionCeiling.sessions([first, second]).map(\.distanceMeters) == [10_000])
        #expect(warnings([long], runs: [first, second]).isEmpty)
        #expect(warnings([long], runs: [first, apart])[long.id]?.longestMeters == 5_000)
    }

    @Test func aDurationIsConvertedWithTheRecentPace() throws {
        let runs = [run(daysAgo: 4, km: 10, minutes: 50)]
        let long = planned(inDays: 3, minutes: 75)

        let warning = try #require(warnings([long], runs: runs)[long.id])
        #expect(warning.isEstimated)
        #expect(warning.plannedMeters == 15_000)
        #expect(warnings([long], runs: []).isEmpty)
    }

    @Test func earlierPlannedRunsRaiseTheCeilingAndAFlaggedOneCountsAtTheCeiling() throws {
        let runs = [run(daysAgo: 5, km: 10)]
        let step = planned(inDays: 3, km: 11)
        let next = planned(inDays: 10, km: 12)
        #expect(warnings([step, next], runs: runs).isEmpty)

        let jump = planned(inDays: 3, km: 15)
        let after = planned(inDays: 10, km: 12)
        let flagged = warnings([jump, after], runs: runs)
        #expect(flagged[jump.id]?.ceilingMeters == 11_000)
        #expect(flagged[after.id] == nil)
    }

    @Test func racesRestAndPastDaysAreNotChecked() {
        let runs = [run(daysAgo: 5, km: 10)]
        let race = planned(inDays: 4, km: 21, purpose: .race)
        let past = planned(inDays: -1, km: 30)
        #expect(warnings([race, past, planned(inDays: 2, purpose: .rest)], runs: runs).isEmpty)
    }
}
