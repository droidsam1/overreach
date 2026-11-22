import Domain
import Foundation
import PresentationKit
import Testing
@testable import TodayPresentation

/// Today's hero (ADR-0041 rule 1): every state except loading has one verb-named primary action.
@MainActor
@Suite("Today hero")
struct TodayHeroTests {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(Date(timeIntervalSince1970: 1_790_000_000), calendar: calendar) }
    private let legs = Routine(name: "Legs A")

    private func plan(
        strength: PlannedStrength? = nil, routine: Routine? = nil, strengthDone: Bool = false, runs: [PlannedRun] = []
    ) -> TodayModel.NextAction? {
        TodayModel.plannedAction(
            strength: strength, routine: routine, strengthDone: strengthDone, runs: runs, format: Format()
        )
    }

    private func completion(_ day: CalendarDay) -> PlannedRunCompletion {
        PlannedRunCompletion(RunActivity(
            id: "run", source: .garmin, startedAt: day.startDate(in: calendar).addingTimeInterval(8 * 3_600),
            durationSeconds: 1_800, distanceMeters: 5_000, averageHeartRate: 140
        ))
    }

    @Test func noPlanGivesNoPlannedAction() {
        #expect(plan() == nil)
    }

    @Test func plannedStrengthStartsTheRoutineByName() {
        let strength = PlannedStrength(day: today, routineID: legs.id)
        #expect(plan(strength: strength, routine: legs) == .startStrength("Legs A", routineID: legs.id))
    }

    @Test func plannedRunStartsTheRun() {
        let run = PlannedRun(day: today, purpose: .easy, durationMinutes: 30)
        #expect(plan(runs: [run]) == .startRun("Easy run · 30 min"))
    }

    @Test func strengthComesFirstThenTheRunOnceItIsDone() {
        let strength = PlannedStrength(day: today, routineID: legs.id)
        let run = PlannedRun(day: today, purpose: .easy, durationMinutes: 30)
        #expect(plan(strength: strength, routine: legs, runs: [run]) == .startStrength("Legs A", routineID: legs.id))
        #expect(plan(strength: strength, routine: legs, strengthDone: true, runs: [run])
            == .startRun("Easy run · 30 min"))
    }

    @Test func everythingDoneOffersAReview() {
        let strength = PlannedStrength(day: today, routineID: legs.id)
        let run = PlannedRun(day: today, purpose: .easy, durationMinutes: 30, completion: completion(today))
        #expect(plan(strength: strength, routine: legs, strengthDone: true, runs: [run]) == .reviewTraining)
        #expect(plan(runs: [run]) == .reviewTraining)
    }

    @Test func plannedRestDaysAreRest() {
        let restStrength = PlannedStrength(day: today)
        let restRun = PlannedRun(day: today, purpose: .rest)
        #expect(plan(strength: restStrength) == .rest)
        #expect(plan(runs: [restRun]) == .rest)
        #expect(plan(strength: restStrength, runs: [PlannedRun(day: today, purpose: .tempo, durationMinutes: 20)])
            == .startRun("Tempo run · 20 min"))
    }

    @Test func aMissingRoutineGivesNoPlannedAction() {
        let strength = PlannedStrength(day: today, routineID: UUID())
        #expect(plan(strength: strength) == nil)
    }

    @Test func everyActionButLoadingHasATitle() async {
        let model = TodayModel(sources: [], calendar: calendar)
        await model.load()

        #expect(model.primaryActionTitle(for: .loading) == nil)
        #expect(model.primaryActionTitle(for: .startStrength("Legs A", routineID: nil)) == "Start Legs A")
        #expect(model.primaryActionTitle(for: .startRun("Easy run · 30 min")) == "Start Easy run · 30 min")
        #expect(model.primaryActionTitle(for: .rest) == "Rest today")
        #expect(model.primaryActionTitle(for: .reviewTraining) == "Review today's training")
        #expect(model.primaryActionTitle(for: .continueWorkout(.resume("Legs A"))) == "Resume workout")
        #expect(model.primaryActionTitle(for: .continueWorkout(.reviewDraft)) == "Review saved workout")
        #expect(model.primaryActionTitle(for: .deload) == "Start deload week")
        #expect(model.primaryActionTitle(for: .retry) == "Try again")
        #expect(model.primaryActionTitle(for: .connectHealth) == "Connect Apple Health")
        #expect(model.primaryActionTitle(for: .connectGarmin) == "Connect your Garmin")
        #expect(model.primaryActionTitle(for: .train) == "Start a workout")
        #expect(model.primaryActionTitle(for: .checkIn) == model.checkInButtonTitle)
    }

    @Test func sparseDataStillHasAPrimaryAction() async {
        let model = TodayModel(sources: [], calendar: calendar)
        #expect(model.primaryActionTitle == nil)

        await model.load()

        #expect(model.nextAction == .connectHealth)
        #expect(model.primaryActionTitle == "Connect Apple Health")
        #expect(model.heroTitle == "Not enough data yet to judge today.")
    }
}
