import Domain
import Foundation
import Testing
@testable import PlanPresentation

/// Real progress in Plan (ADR-0041 rule 7, issue #187).
@Suite("Plan progress")
struct PlanProgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    private let legs = UUID()
    private let push = UUID()

    /// Wednesday 18 November 2026 at noon: the week runs from Monday 16 to Sunday 22.
    private var now: Date { day(18).startDate(in: calendar).addingTimeInterval(12 * 3_600) }

    private func day(_ number: Int) -> CalendarDay {
        CalendarDay(calendar.date(from: DateComponents(year: 2026, month: 11, day: number))!, calendar: calendar)
    }

    private func session(_ routine: UUID, on number: Int) -> StrengthSession {
        let start = day(number).startDate(in: calendar).addingTimeInterval(8 * 3_600)
        return StrengthSession(
            name: "Gym", startedAt: start, endedAt: start.addingTimeInterval(3_600), routineID: routine
        )
    }

    private func linked(on number: Int) -> PlannedRunCompletion {
        PlannedRunCompletion(RunActivity(
            id: "run-\(number)", source: .garmin,
            startedAt: day(number).startDate(in: calendar).addingTimeInterval(7 * 3_600),
            durationSeconds: 1_800, distanceMeters: 5_000, averageHeartRate: 140
        ))
    }

    private func progress(
        strength: [PlannedStrength] = [], runs: [PlannedRun] = [], sessions: [StrengthSession] = [],
        blockWeek: (planned: Int, done: Int)? = nil, block: TrainingBlock? = nil
    ) -> PlanProgress? {
        PlanProgress.make(
            strength: strength, runs: runs, sessions: sessions, blockWeek: blockWeek, currentBlock: block, now: now,
            calendar: calendar
        )
    }

    @Test func noPlanShowsNoProgress() {
        #expect(progress() == nil)
        #expect(progress(sessions: [session(legs, on: 16)]) == nil)
    }

    @Test func countsDoneAgainstPlannedThisWeek() throws {
        let week = try #require(progress(
            strength: [PlannedStrength(day: day(16), routineID: legs), PlannedStrength(day: day(20), routineID: push)],
            runs: [
                PlannedRun(day: day(17), purpose: .easy, durationMinutes: 30, completion: linked(on: 17)),
                PlannedRun(day: day(19), purpose: .tempo, durationMinutes: 20),
            ],
            sessions: [session(legs, on: 16)]
        )?.week)
        #expect(week.title == "This week: 2 of 4 sessions")
        #expect(week.accessibilityLabel == "2 of 4 sessions done this week")
        #expect(week.fraction == 0.5)
    }

    @Test func restAndPostponedEntriesCountAsHandled() throws {
        let week = try #require(progress(
            strength: [PlannedStrength(day: day(16), routineID: legs), PlannedStrength(day: day(18))],
            runs: [
                PlannedRun(day: day(17), purpose: .rest),
                PlannedRun(day: day(16), purpose: .easy, durationMinutes: 30, postponed: true),
            ],
            sessions: [session(legs, on: 16)]
        )?.week)
        #expect(week.title == "This week: 1 of 1 sessions")
        #expect(week.fraction == 1)
    }

    @Test func unlinkedActivitiesDoNotCompleteAnEntry() throws {
        let week = try #require(progress(
            strength: [PlannedStrength(day: day(16), routineID: legs)],
            runs: [PlannedRun(day: day(17), purpose: .easy, durationMinutes: 30)],
            // Another routine on the planned day, and the planned routine on a different day.
            sessions: [session(push, on: 16), session(legs, on: 17)]
        )?.week)
        #expect(week.title == "This week: 0 of 2 sessions")
        #expect(week.fraction == 0)
    }

    @Test func entriesOutsideThisWeekAreLeftOut() {
        let strength = [PlannedStrength(day: day(15), routineID: legs), PlannedStrength(day: day(23), routineID: legs)]
        #expect(progress(strength: strength) == nil)
    }

    @Test func withoutDatedEntriesTheBlockTargetCounts() throws {
        let week = try #require(progress(blockWeek: (planned: 3, done: 1))?.week)
        #expect(week.title == "This week: 1 of 3 sessions")
        #expect(week.accessibilityLabel == "1 of 3 sessions done this week")
    }

    @Test func showsTheWeekOfADeclaredBlock() throws {
        let block = TrainingBlock(focus: .strength, start: day(9), plannedWeeks: 5, isDeclared: true)
        let line = try #require(progress(block: block)?.block)
        #expect(line.title == "Block: week 2 of 5")
        #expect(line.accessibilityLabel == "Week 2 of 5 of the block")
        #expect(line.fraction == 0.4)
    }

    @Test func detectedOpenEndedOrFinishedBlocksShowNoWeek() {
        let detected = TrainingBlock(focus: .strength, start: day(9), plannedWeeks: 5, isDeclared: false)
        let openEnded = TrainingBlock(focus: .strength, start: day(9), isDeclared: true)
        let finished = TrainingBlock(focus: .strength, start: day(2), plannedWeeks: 2, isDeclared: true)
        #expect(progress(block: detected) == nil)
        #expect(progress(block: openEnded) == nil)
        #expect(progress(block: finished) == nil)
    }
}
