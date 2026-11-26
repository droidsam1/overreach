import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

@MainActor
@Suite("Warm-up sets in the logger")
struct WarmUpLoggingTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], secondaryMuscles: [.triceps],
                                 equipment: .barbell)
    private let incline = Exercise(name: "Incline Press", primaryMuscles: [.chest], equipment: .dumbbell)
    private let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func makeModel(mainLift: Bool = false) async -> (WorkoutModel, TestStore) {
        let history = StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-3 * 86_400),
            entries: [bench, incline, squat].map { exercise in
                ExerciseEntry(exerciseID: exercise.id, sets: [10, 10, 10].map { WorkoutSet(weightKg: 60, reps: $0, rpe: 8) })
            }
        )
        let store = TestStore(exercises: [bench, incline, squat], sessions: [history])
        if mainLift {
            try? await store.save(ProgressionSettings(for: incline, isMainLift: true), for: incline.id)
        }
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start()
        return (model, store)
    }

    @Test func theFirstExerciseForItsMusclesGetsWarmUpsBeforeTheWorkingSets() async throws {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)

        let exercise = try #require(model.exercises.first)
        let warmUps = exercise.sets.filter(\.isWarmUp)
        #expect(warmUps.count == 2)
        #expect(exercise.sets.prefix(2).allSatisfy { $0.isWarmUp })
        #expect(warmUps.map(\.weightKg) == [30, 47.5])
        #expect(exercise.sets.map { exercise.number(of: $0.id) } == [1, 2, 1, 2, 3])
        #expect(!exercise.canAddWarmUp)
        let reason = try #require(exercise.summary(format: format).reasons.last)
        #expect(reason.hasPrefix("Warm-up: 2 sets with few reps"))
        #expect(reason.hasSuffix("(moderate evidence)"))
    }

    @Test func laterExercisesForTheSameMusclesGetThemOnDemand() async throws {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: incline.id)
        await model.add(exerciseID: squat.id)

        let second = model.exercises[1]
        #expect(!second.sets.contains { $0.isWarmUp })
        #expect(second.canAddWarmUp)
        #expect(model.exercises[2].sets.contains { $0.isWarmUp })  // new muscles

        model.addWarmUp(to: second.id)
        let warmed = model.exercises[1]
        #expect(warmed.sets.filter(\.isWarmUp).count == 1)  // primed: one set close to the load
        #expect(warmed.sets.first?.isWarmUp == true)
        #expect(try #require(warmed.summary(format: format).reasons.last).hasPrefix("Warm-up: one set"))
    }

    @Test func theWarmUpButtonAddsTheSuggestionThenOneSetAtATime() async throws {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: incline.id)
        let second = model.exercises[1]
        #expect(second.addWarmUpTitle == "Add suggested warm-up")

        model.addWarmUp(to: second.id)
        #expect(model.exercises[1].addWarmUpTitle == "Add warm-up set")
        model.exercises[1].sets[0].weightKg = 40
        model.addWarmUp(to: second.id)

        let sets = model.exercises[1].sets
        #expect(sets.map(\.isWarmUp) == [true, true, false, false, false])
        #expect(sets[1].weightKg == 40)  // copies the last warm-up
        #expect(sets[1].reps == sets[0].reps)
        #expect(!sets[1].isDone)
    }

    @Test func deletedWarmUpsAreOfferedAgain() async throws {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        let id = model.exercises[0].id
        model.exercises[0].sets.removeAll(where: \.isWarmUp)
        #expect(model.exercises[0].addWarmUpTitle == "Add suggested warm-up")

        model.addWarmUp(to: id)
        #expect(model.exercises[0].sets.filter(\.isWarmUp).map(\.weightKg) == [30, 47.5])
    }

    @Test func mainLiftsGetThemEvenWhenTheMusclesAreWarm() async {
        let (model, _) = await makeModel(mainLift: true)
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: incline.id)
        #expect(model.exercises[1].sets.contains { $0.isWarmUp })
    }

    @Test func warmUpsAreSavedApartAndDoNotStartTheRest() async throws {
        let (model, store) = await makeModel()
        await model.add(exerciseID: bench.id)
        let exercise = model.exercises[0]
        for set in exercise.sets.prefix(3) {
            model.setDone(true, set: set.id, in: exercise.id)
            if set.isWarmUp {
                #expect(!model.rest.isActive)
            }
        }
        #expect(model.rest.isActive)  // after the first working set

        #expect(await model.finish())
        let saved = try #require(try await store.sessions(from: now.addingTimeInterval(-60), to: .distantFuture).first)
        #expect(saved.entries.first?.sets.map(\.kind) == [.warmup, .warmup, .working])
    }

    @Test func anExerciseIsCompleteAfterAllItsSetsAreDone() async {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        let exercise = model.exercises[0]
        #expect(!exercise.isComplete)

        for set in exercise.workingSets {
            model.setDone(true, set: set.id, in: exercise.id)
        }
        #expect(!model.exercises[0].isComplete)

        for set in exercise.sets where set.isWarmUp {
            model.setDone(true, set: set.id, in: exercise.id)
        }
        #expect(model.exercises[0].isComplete)

        model.addSet(to: exercise.id)
        #expect(!model.exercises[0].isComplete)
    }

    @Test func addingASetCopiesTheLastWorkingSet() async {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        model.addSet(to: model.exercises[0].id)
        let last = model.exercises[0].sets.last
        #expect(last?.isWarmUp == false)
        #expect(last?.weightKg == 60)
    }

    @Test func theGeneralWarmUpIsOnlySuggestedBeforeTheFirstSet() async throws {
        let (model, _) = await makeModel()
        await model.add(exerciseID: bench.id)
        #expect(model.generalWarmUpTip?.hasSuffix("(moderate evidence)") == true)

        let exercise = model.exercises[0]
        model.setDone(true, set: exercise.sets[0].id, in: exercise.id)
        #expect(model.generalWarmUpTip == nil)
    }
}
