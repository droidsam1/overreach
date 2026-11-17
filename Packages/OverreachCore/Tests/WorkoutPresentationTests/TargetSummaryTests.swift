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
        #expect(summary.targetLine.hasPrefix("Target: 62.5 kg × 8/8/8 @ RPE "))  // top of 8–12 reached → +2.5 kg
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
}
