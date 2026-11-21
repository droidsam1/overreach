import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

@MainActor
@Suite("Workout screen state")
struct TargetSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell, aliases: ["press banca"])
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func session(daysAgo: Double, weight: Double, reps: [Int]) -> StrengthSession {
        StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: 8) })]
        )
    }

    private func model(history: [StrengthSession] = []) async -> WorkoutModel {
        let store = TestStore(exercises: [bench], sessions: history)
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start()
        return model
    }

    @Test func summaryDescribesTargetFocusRestAndReasons() async throws {
        let model = await model(history: [session(daysAgo: 3, weight: 60, reps: [12, 12, 12])])
        await model.add(exerciseID: bench.id)

        let summary = try #require(model.exercises.first).summary(format: format)
        #expect(summary.targetLine.hasPrefix("Target: 60 kg × 12/12/12 @ RPE "))
        #expect(summary.focusLine.lowercased().contains("rest "))
        #expect(!summary.reasons.isEmpty)
        #expect(summary.reasons.allSatisfy { $0.hasSuffix("evidence)") || $0.hasSuffix("heuristic)") })
        #expect(!summary.isStalled)
        #expect(summary.stallSuggestions.isEmpty)
    }

    @Test func inferredFocusIsMarkedAsDetected() async throws {
        let history = (1...3).map { session(daysAgo: Double($0 * 3), weight: 100, reps: [3, 3, 3]) }
        let model = await model(history: history)
        await model.add(exerciseID: bench.id)

        let exercise = try #require(model.exercises.first)
        #expect(exercise.isFocusInferred)
        #expect(exercise.summary(format: format).focusLine.contains("(detected)"))
    }

    @Test func withoutHistoryTheFocusLineIsOnlyTheRest() async throws {
        let model = await model()
        await model.add(exerciseID: bench.id)

        let summary = try #require(model.exercises.first).summary(format: format)
        #expect(summary.focusLine.hasPrefix("Rest "))
        #expect(summary.status == nil)
    }

    @Test func choicesAndSetNumbers() async throws {
        let model = await model()
        #expect(model.exerciseChoices.map(\.name) == ["Bench Press"])
        #expect(model.exerciseChoices.first?.searchTerms == ["Bench Press", "press banca"])
        #expect(model.focusOptions.map(\.value) == TrainingFocus.allCases)

        await model.add(exerciseID: bench.id)
        let exercise = try #require(model.exercises.first)
        #expect(exercise.sets.map { exercise.number(of: $0.id) } == Array(1...exercise.sets.count))
    }

    @Test func unknownExerciseIDsAreIgnored() async {
        let model = await model()
        await model.add(exerciseID: UUID())
        #expect(model.exercises.isEmpty)
    }

    @Test func changingTheFocusKeepsExercisesWithCompletedSets() async throws {
        let model = await model()
        await model.add(exerciseID: bench.id)
        model.exercises[0].sets[0].isDone = true
        let before = model.exercises[0].sets

        await model.setSessionFocus(.strength)

        #expect(model.sessionFocus == .strength)
        #expect(model.exercises[0].sets == before)
    }

    @Test func lastTimeShowsTheLatestSetsNextToTheTarget() async throws {
        let older = session(daysAgo: 7, weight: 55, reps: [10, 10, 10])
        // The latest session counts even when it was left out of progression, and warm-ups are not shown.
        let latest = StrengthSession(
            name: "Push", startedAt: now.addingTimeInterval(-2 * 86_400),
            entries: [ExerciseEntry(
                exerciseID: bench.id,
                sets: [
                    WorkoutSet(kind: .warmup, weightKg: 40, reps: 5),
                    WorkoutSet(weightKg: 60, reps: 8, rpe: 8),
                    WorkoutSet(weightKg: 60, reps: 8, rpe: 8.5),
                    WorkoutSet(weightKg: 62.5, reps: 6, rpe: 9),
                ],
                countsForProgression: false
            )]
        )
        let model = await model(history: [older, latest])
        await model.add(exerciseID: bench.id)

        let line = try #require(model.exercises.first).summary(format: format).lastTimeLine
        #expect(line.hasPrefix("Last time ("))
        #expect(line.hasSuffix("): 60 kg × 8/8 · 62.5 kg × 6"))
    }

    @Test func lastTimeValuesFillOnlyOpenWorkingSetsWhenAsked() async throws {
        let model = await model(history: [session(daysAgo: 3, weight: 60, reps: [12, 11, 10])])
        await model.add(exerciseID: bench.id)
        let id = try #require(model.exercises.first).id
        let sets = try #require(model.exercises.first).workingSets
        model.setDone(true, set: sets[0].id, in: id)
        let edited = try #require(model.exercises[0].sets.firstIndex { $0.id == sets[1].id })
        model.exercises[0].sets[edited].weightKg = 70
        model.exercises[0].sets[edited].rpe = 9

        #expect(model.exercises[0].canUseLastTime)
        model.useLastTime(for: id)

        let filled = model.exercises[0].workingSets
        #expect(filled[0].weightKg == sets[0].weightKg)  // done sets are never touched
        #expect(filled[1].weightKg == 60)
        #expect(filled[1].reps == 11)
        #expect(filled[1].rpe == 9)  // effort stays as entered
        #expect(filled[2].reps == 10)
        #expect(!model.exercises[0].canUseLastTime)
    }

    @Test func withoutHistoryThereAreNoLastTimeValuesToUse() async throws {
        let model = await model()
        await model.add(exerciseID: bench.id)

        #expect(!model.exercises[0].canUseLastTime)
    }

    @Test func lastTimeShowsTheEffortWhenEverySetSharesIt() async throws {
        let model = await model(history: [session(daysAgo: 3, weight: 60, reps: [12, 12, 11])])
        await model.add(exerciseID: bench.id)

        let line = try #require(model.exercises.first).summary(format: format).lastTimeLine
        #expect(line.hasSuffix("): 60 kg × 12/12/11 @ RPE 8"))
    }

    @Test func withoutHistoryLastTimeSaysSo() async throws {
        let model = await model()
        await model.add(exerciseID: bench.id)

        let summary = try #require(model.exercises.first).summary(format: format)
        #expect(summary.lastTimeLine == "Last time: no sets logged yet")
    }
}
