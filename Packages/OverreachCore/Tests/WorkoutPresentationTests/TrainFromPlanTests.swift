import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
@Suite("Training from a plan")
struct TrainFromPlanTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let row = Exercise(name: "Row", primaryMuscles: [.back], equipment: .cable)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private var lastBench: StrengthSession {
        StrengthSession(
            name: "Push", startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8), WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
                WorkoutSet(weightKg: 60, reps: 12, rpe: 8),
            ])]
        )
    }

    private var heavyUpper: Routine {
        Routine(name: "Upper (strength)", focus: .strength, exerciseIDs: [bench.id, row.id], prescriptions: [
            RoutinePrescription(
                exerciseID: bench.id, scheme: .rpeBased(sets: 5, reps: 3, targetRPE: 8), restSeconds: 120
            ),
        ])
    }

    @Test func aRoutinePrescriptionSetsSetsAndRepsAndTheEngineSetsTheLoad() async throws {
        let store = TestStore(exercises: [bench, row], sessions: [lastBench])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })

        await model.start(heavyUpper)

        let benchDraft = try #require(model.exercises.first { $0.exercise.id == bench.id })
        #expect(benchDraft.workingSets.count == 5)
        #expect(benchDraft.workingSets.allSatisfy { $0.reps == 3 })
        let load = try #require(benchDraft.workingSets.first?.weightKg)
        #expect(load > 60)  // three reps at RPE 8 are heavier than twelve
        #expect(benchDraft.isPrescribedByRoutine)
        #expect(benchDraft.summary.focusLine.hasSuffix("sets and reps from the routine"))
        let workingSet = try #require(benchDraft.workingSets.first)
        model.setDone(true, set: workingSet.id, in: benchDraft.id)
        #expect(model.rest.state(at: now)?.remaining == "2:00")

        let rowDraft = try #require(model.exercises.first { $0.exercise.id == row.id })
        #expect(!rowDraft.isPrescribedByRoutine)

        // The same exercise outside the routine follows its own settings again.
        model.discard()
        model.start()
        await model.add(bench)
        #expect(model.exercises.first?.workingSets.count == 3)
        #expect(model.exercises.first?.isPrescribedByRoutine == false)
    }

    @Test func theSavedSessionRemembersItsRoutine() async throws {
        let store = TestStore(exercises: [bench, row])
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        let routine = heavyUpper
        await model.start(routine)
        model.exercises[0].sets[model.exercises[0].sets.count - 1].weightKg = 80
        model.exercises[0].sets[model.exercises[0].sets.count - 1].isDone = true

        #expect(await model.finish())
        let saved = try #require(try await store.sessions(from: .distantPast, to: .distantFuture).first)
        #expect(saved.routineID == routine.id)
    }

    @Test func upNextFollowsThePlan() async throws {
        let upper = heavyUpper
        let lower = Routine(name: "Lower", exerciseIDs: [row.id])
        let today = CalendarDay(now, calendar: calendar)
        let blockStart = today.adding(days: -9, calendar: calendar)
        let doneUpper = StrengthSession(
            name: upper.name, startedAt: now.addingTimeInterval(-86_400), routineID: upper.id
        )
        let store = TestStore(exercises: [bench, row], sessions: [doneUpper], routines: [upper, lower])
        var profile = AthleteProfile()
        profile.declaredBlocks = [TrainingBlock(
            focus: .strength, start: blockStart, plannedWeeks: 6, isDeclared: true, name: "Strength",
            routineIDs: [upper.id, lower.id]
        )]
        try await store.save(profile)
        let fixedNow = now
        let model = RoutinesModel(
            routines: store, exercises: store, profiles: store, workouts: store, calendar: calendar,
            clock: { fixedNow }
        )

        await model.load()

        let next = try #require(model.upNext)
        #expect(next.routine.id == lower.id)
        #expect(next.title == "Lower")
        #expect(next.detail == "Strength · week 2 of 6")
        #expect(next.exerciseList == "Row")
    }

    @Test func noPlanNoUpNext() async {
        let store = TestStore(exercises: [bench], routines: [heavyUpper])
        let model = RoutinesModel(routines: store, exercises: store, profiles: store, workouts: store)
        await model.load()
        #expect(model.upNext == nil)

        let withoutProfiles = RoutinesModel(routines: store, exercises: store)
        await withoutProfiles.load()
        #expect(withoutProfiles.upNext == nil)
    }

    @Test func editingARoutineKeepsItsPrescriptions() async throws {
        let routine = heavyUpper
        let store = TestStore(exercises: [bench, row], routines: [routine])
        let model = RoutinesModel(routines: store, exercises: store)
        await model.load()
        let editor = try #require(model.editor(for: routine.id))
        editor.name = "Upper heavy"
        #expect(await editor.save())

        let saved = try #require(try await store.allRoutines().first)
        #expect(saved.name == "Upper heavy")
        #expect(saved.prescriptions == routine.prescriptions)
    }
}
