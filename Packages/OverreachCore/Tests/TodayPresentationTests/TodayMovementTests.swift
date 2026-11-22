import Analytics
import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

private struct StepsSource: MetricsSource {
    let kind = DataSourceKind.garmin
    let days: [DailyMetrics]
    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct WalksSource: ActivitySource {
    let walks: [WalkBout]
    var fails = false
    func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        if fails { throw CocoaError(.fileReadUnknown) }
        return [DailyActivity(day: range.upperBound, walks: walks)]
    }
}

@MainActor
@Suite("Today: steps and walks against the usual day")
struct TodayMovementTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    /// Four weeks at 9,000 steps, then `recent` for the last three complete days, and 1,200 steps so far today.
    private func source(recent: Int) -> StepsSource {
        let days = (-28...0).map { offset in
            var metrics = DailyMetrics(day: today.adding(days: offset, calendar: calendar), sources: [.garmin])
            metrics.steps = offset == 0 ? 1_200 : offset >= -3 ? recent : 9_000
            return metrics
        }
        return StepsSource(days: days)
    }

    /// The same walk recorded by Apple Health and Garmin every day, except yesterday's long hike.
    private func walks(hikeMinutes: Double) -> [WalkBout] {
        (-28 ... -1).flatMap { offset -> [WalkBout] in
            let start = today.adding(days: offset, calendar: calendar).startDate(in: calendar)
                .addingTimeInterval(8 * 3_600)
            let minutes = offset == -1 ? hikeMinutes : 30
            return [WalkBout(start: start, durationSeconds: minutes * 60, source: .garmin),
                    WalkBout(start: start.addingTimeInterval(60), durationSeconds: minutes * 60, source: .appleHealth)]
        }
    }

    @Test func stepsCompareWithTheUsualDayOnceThereIsEnoughHistory() async {
        let model = TodayModel(sources: [source(recent: 9_000)], calendar: calendar, format: format)
        await model.load(now: now)
        #expect(model.stepsCaption == "Usually 9,000 a day")
        #expect(model.movementNotes.isEmpty)
    }

    @Test func aLongHikeYesterdayIsMentionedOnceAcrossSources() async {
        let model = TodayModel(sources: [source(recent: 9_000)],
                               activity: [WalksSource(walks: walks(hikeMinutes: 150))], calendar: calendar,
                               format: format)
        await model.load(now: now)
        #expect(model.movementNotes == [MovementNote(
            text: "Yesterday you walked 150 min, 120 min more than usual. "
                + "Your legs may be more tired for leg work or a run.",
            evidence: "coaching heuristic"
        )])
    }

    @Test func threeVeryLowDaysSuggestAWalk() async {
        let model = TodayModel(sources: [source(recent: 2_000)], calendar: calendar, format: format)
        await model.load(now: now)
        #expect(model.movementNotes.map(\.text) == [
            "About 2,000 steps a day over the last 3 days, well under your usual 9,000. "
                + "Very little daily movement can blunt what you get from training: a walk today helps.",
        ])
    }

    @Test func aFailedWalkReadLeavesTheStepsAlone() async {
        let model = TodayModel(sources: [source(recent: 9_000)], activity: [WalksSource(walks: [], fails: true)],
                               calendar: calendar, format: format)
        await model.load(now: now)
        #expect(model.steps == 1_200)
        #expect(model.stepsCaption == "Usually 9,000 a day")
        #expect(model.movementNotes.isEmpty)
    }

    @Test func aWalkingSpikeAddsAWarmupCueForLegWorkAndRuns() {
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps])
        let routine = Routine(name: "Legs", exerciseIDs: [squat.id])
        let strength = PlannedStrength(day: today, routineID: routine.id)
        let strengthDay = MovementNote.Schedule(strength: strength, routine: routine, exercises: [squat], runs: [])
        let runDay = MovementNote.Schedule(strength: nil, routine: nil, exercises: [],
                                           runs: [PlannedRun(day: today, purpose: .tempo)])
        let restDay = MovementNote.Schedule(strength: PlannedStrength(day: today), routine: nil,
                                            exercises: [], runs: [])
        #expect(restDay.isRest)
        #expect(!restDay.hasLegSession)
        for schedule in [strengthDay, runDay] {
            #expect(!schedule.isRest)
            let notes = MovementNote.notes(
                signals: [.walkingSpike(day: today, minutes: 120, baselineMinutes: 30)],
                suggestsRecoveryWalk: false, routine: WalkingRoutine(), today: today, format: format,
                hasLegSession: schedule.hasLegSession
            )
            #expect(notes.last?.text ==
                    "Start with an easy warm-up and check how your legs feel before increasing the effort.")
        }
    }

    @Test func aUsualWalkDoesNotAddAdvice() async {
        let walk = WalkBout(start: now.addingTimeInterval(-2_400), durationSeconds: 1_800, source: .garmin)
        let model = TodayModel(sources: [source(recent: 9_000)],
                               activity: [WalksSource(walks: walks(hikeMinutes: 30) + [walk])],
                               calendar: calendar, format: format)
        await model.load(now: now)
        #expect(model.movementNotes.isEmpty)
    }

    @Test func aRedDayAsksToKeepTheDogWalksEasy() {
        let notes = { (routine: WalkingRoutine) in
            MovementNote.notes(signals: [], suggestsRecoveryWalk: true, routine: routine, today: self.today,
                               format: self.format).map(\.text)
        }
        #expect(notes(WalkingRoutine(hasDog: true, dogName: "Nanoq", walksAreFixed: true)) == [
            "Keep your walks with Nanoq easy today.",
        ])
        #expect(notes(WalkingRoutine(hasDog: true)) == [
            "Keep your walks with your dog easy today.",
        ])
        #expect(notes(WalkingRoutine(walksAreFixed: true)) == [
            "Keep your usual walks easy today. Easy movement eases soreness and fatigue a little more than full rest.",
        ])
        #expect(notes(WalkingRoutine()) == [
            "An easy 20–40 min walk can ease soreness and fatigue a little more than full rest.",
        ])
        #expect(MovementNote.notes(signals: [], suggestsRecoveryWalk: false, routine: WalkingRoutine(), today: today,
                                   format: format).isEmpty)
    }
}
