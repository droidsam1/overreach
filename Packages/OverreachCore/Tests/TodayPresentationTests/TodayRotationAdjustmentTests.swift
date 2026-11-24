import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation
import WorkoutPresentation

@MainActor
@Suite("Today rotation after a recorded run")
struct TodayRotationAdjustmentTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_093_200)
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench", primaryMuscles: [.chest], equipment: .barbell)

    private func history(
        allHeavy: Bool = false, templates: Bool = true, torsoFirst: Bool = false
    ) -> (TestStore, [Routine]) {
        let routines = ["A", "B", "C", "D"].enumerated().map { index, name in
            let heavy = allHeavy || (torsoFirst ? index == 1 : index < 2)
            return Routine(name: name, exerciseIDs: [heavy ? squat.id : bench.id])
        }
        let cycle = routines + routines
        let sessions = cycle.enumerated().map { index, routine in
            let start = now.addingTimeInterval(-Double((cycle.count - index) * 2) * 86_400)
            return StrengthSession(
                name: routine.name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
                entries: routine.exerciseIDs.map {
                    ExerciseEntry(exerciseID: $0, sets: (0..<3).map { _ in
                        WorkoutSet(weightKg: 100, reps: 5, rpe: 7)
                    })
                }, routineID: templates ? routine.id : nil
            )
        }
        return (TestStore(exercises: [squat, bench], sessions: sessions, routines: templates ? routines : []), routines)
    }

    private func load(
        _ store: TestStore, at date: Date? = nil, hard: Bool = true,
        hoursSinceStart: Double = 30, hasEarlierRun: Bool = true, dismissed: CalendarDay? = nil,
        saveDismissal: @escaping @MainActor (CalendarDay) -> Void = { _ in }
    ) async -> TodayModel {
        let date = date ?? now
        let run = RunActivity(
            id: "recent", source: .garmin, name: "Park run",
            startedAt: now.addingTimeInterval(-hoursSinceStart * 3_600), durationSeconds: 1_800,
            distanceMeters: 4_000, elevationLossMeters: 25, aerobicTrainingEffect: hard ? 4.2 : 2
        )
        let earlier = RunActivity(
            id: "earlier", source: .garmin, startedAt: now.addingTimeInterval(-7 * 86_400),
            durationSeconds: 1_800, distanceMeters: 4_000
        )
        let runs = hasEarlierRun ? [earlier, run] : [run]
        let model = TodayModel(
            sources: [RotationRunSource(day: CalendarDay(date, calendar: calendar), runs: runs)],
            profiles: store, workouts: store, exercises: store, routines: store,
            dismissedRotationDay: dismissed, saveDismissedRotationDay: saveDismissal,
            calendar: calendar, format: Format(locale: Locale(identifier: "en_US"))
        )
        await model.load(now: date)
        return model
    }

    @Test func aLightRunKeepsThePlanAndExplainsItOnlyInWhy() async {
        let (store, routines) = history()
        let model = await load(store, hard: false)
        #expect(model.nextAction == .startStrength(routines[0]))
        #expect(model.rotationOffer == nil)
        #expect(model.rotationExplanation.first == "Keep A as planned.")
        #expect(model.rotationExplanation.contains { $0.contains("Park run") && $0.contains("29.5 hours ago") })
        #expect(model.rotationExplanation.contains("Elevation: 25 m descent"))
        #expect(model.rotationExplanation.contains { $0.hasPrefix("Previous leg session: B") })
        #expect(model.rotationExplanation.contains("Readiness: Green · coaching heuristic"))
    }

    @Test func aCloseRunWithUnknownExposureDoesNotMoveTheLegSession() async {
        let (store, routines) = history()
        let model = await load(store, hard: false, hoursSinceStart: 20, hasEarlierRun: false)
        #expect(model.nextAction == .startStrength(routines[0]))
        #expect(model.rotationOffer == nil)
        #expect(model.rotationExplanation.contains("Recent running exposure is unknown."))
        #expect(model.rotationExplanation.contains { $0.contains("19.5 hours ago") })
    }

    @Test func aCloseHardRunReconsidersLegWorkAndPreservesTorso() async {
        let (legs, _) = history()
        let legsModel = await load(legs, hoursSinceStart: 20)
        #expect(legsModel.rotationOffer != nil)

        let (torso, routines) = history(torsoFirst: true)
        let torsoModel = await load(torso, hoursSinceStart: 20)
        #expect(torsoModel.nextAction == .startStrength(routines[0]))
        #expect(torsoModel.rotationOffer == nil)
    }

    @Test func acceptingASwapStartsTheLighterRoutineAndRecordsItsOriginalDay() async throws {
        let (store, routines) = history()
        let model = await load(store)
        #expect(model.rotationOffer?.title.contains("do C today, A on") == true)
        #expect(model.nextAction == .startStrength(routines[0]))
        let started = await model.acceptRotation()
        #expect(started == routines[2])
        let saved = try #require(await store.profile().rotationAdjustments.first)
        #expect(saved.day == today)
        #expect(saved.kind == .swap(from: routines[0].id.uuidString, to: routines[2].id.uuidString))
        #expect(saved.swapDay == today.adding(days: 4, calendar: calendar))
        let relaunched = await load(store)
        #expect(relaunched.rotationOffer == nil)
        #expect(relaunched.nextAction == .startStrength(routines[2]))
    }

    @Test func aSwapFromHistoryCanStartWithoutChangingTheSlotIdentity() async throws {
        let (store, _) = history(templates: false)
        var profile = AthleteProfile()
        profile.deloadPostponedUntil = today.adding(days: 7, calendar: calendar)
        try await store.save(profile)
        let model = await load(store)
        let accepted = await model.acceptRotation()
        let routine = try #require(accepted)
        #expect(routine.name == "C")
        #expect(model.startsFromRotationHistory(routine))

        let date = now
        let workout = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { date })
        await workout.start(routine, startsFromRotationHistory: model.startsFromRotationHistory(routine))
        let draft = try #require(workout.exercises.first)
        let set = try #require(draft.workingSets.first)
        workout.setDone(true, set: set.id, in: draft.id)
        #expect(await workout.finish())
        let saved = await store.sessions(from: now, to: now)
        #expect(saved.first?.name == "C")
        #expect(saved.first?.routineID == nil)

        let interveningDay = now.addingTimeInterval(2 * 86_400)
        let next = await load(store, at: interveningDay)
        guard case let .startStrength(intervening) = next.nextAction else {
            Issue.record("The rotation should still recognize the intervening session")
            return
        }
        #expect(intervening.name == "B")
        let interveningWorkout = WorkoutModel(
            workouts: store, exercises: store, progression: store, clock: { interveningDay }
        )
        await interveningWorkout.start(intervening, startsFromRotationHistory: true)
        let legs = try #require(interveningWorkout.exercises.first)
        let working = try #require(legs.workingSets.first)
        interveningWorkout.setDone(true, set: working.id, in: legs.id)
        #expect(await interveningWorkout.finish())
        let destination = await load(store, at: now.addingTimeInterval(4 * 86_400))
        guard case let .startStrength(heavy) = destination.nextAction else {
            Issue.record("The rotation should recognize the moved session")
            return
        }
        #expect(heavy.name == "A")
    }

    @Test func acceptingAPostponementMovesTheLiftAndCapsItIfTheRunStillMatters() async throws {
        let (store, routines) = history(allHeavy: true)
        let model = await load(store)
        #expect(model.rotationOffer?.acceptTitle == "Postpone session")
        let started = await model.acceptRotation()
        #expect(started == nil)
        #expect(model.nextAction == .rest)
        #expect(await store.profile().rotationAdjustments.map(\.kind) == [.postpone(days: 1)])

        // The same run is still within the carry-over window early on the shifted day.
        let shifted = now.addingTimeInterval(86_400 - 10 * 3_600)
        let nextDay = await load(store, at: shifted)
        #expect(nextDay.nextAction == .startStrength(routines[0]))
        #expect(nextDay.rotationOffer == nil)
        let cap = try #require(nextDay.rotationCap(for: routines[0]))
        #expect(cap.maximumRPE == 8)
        #expect(cap.carryover == .notable)

        let workout = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { shifted })
        await workout.start(routines[0], rotationCap: cap)
        let draft = try #require(workout.exercises.first)
        #expect(draft.target.sets.allSatisfy { ($0.weightKg ?? 0) <= 100 && $0.targetRPE <= 8 })
        let set = try #require(draft.workingSets.first)
        workout.setDone(true, set: set.id, in: draft.id)
        #expect(await workout.finish())
        let sessions = await store.sessions(from: shifted, to: shifted)
        #expect(sessions.first?.entries.first?.countsForProgression == false)
        #expect(sessions.first?.rotationCap == cap)
    }

    @Test func keepPlanSurvivesRelaunchAndLeavesTheOriginalRoutine() async {
        let (store, routines) = history()
        var dismissed: CalendarDay?
        let model = await load(store, saveDismissal: { dismissed = $0 })
        #expect(model.rotationOffer != nil)
        model.dismissRotation()
        #expect(model.rotationOffer == nil)
        #expect(dismissed == today)
        let relaunched = await load(store, dismissed: dismissed)
        #expect(relaunched.rotationOffer == nil)
        #expect(relaunched.nextAction == .startStrength(routines[0]))
        #expect(await store.profile().rotationAdjustments.isEmpty)
        let stale = await load(store, dismissed: today.adding(days: -1, calendar: calendar))
        #expect(stale.rotationOffer != nil)
    }

    @Test func failedAcceptanceLeavesTheOfferAvailableToRetry() async {
        let (store, routines) = history()
        let model = await load(store)
        await store.setFailing(true)
        let started = await model.acceptRotation()
        #expect(started == nil)
        #expect(model.rotationOffer != nil)
        #expect(model.rotationSaveError != nil)
        #expect(model.nextAction == .startStrength(routines[0]))
    }
}

private struct RotationRunSource: MetricsSource {
    let kind = DataSourceKind.garmin
    let day: CalendarDay
    let runs: [RunActivity]

    func isAvailable() async -> Bool { true }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        var metrics = DailyMetrics(day: day, sources: [kind])
        metrics.sleepSeconds = 8 * 3_600
        return [metrics]
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { runs }
}
