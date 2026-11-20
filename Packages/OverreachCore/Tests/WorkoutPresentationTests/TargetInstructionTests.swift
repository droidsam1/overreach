import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

/// The reasons under a target say what to do today, with the numbers of the target.
@MainActor
@Suite("Target instructions")
struct TargetInstructionTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func session(daysAgo: Double, weight: Double, reps: [Int]) -> StrengthSession {
        StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(
                exerciseID: bench.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: 8) }
            )]
        )
    }

    private func firstReason(history: [StrengthSession]) async throws -> String {
        let store = TestStore(exercises: [bench], sessions: history)
        let fixedNow = now
        let model = WorkoutModel(workouts: store, exercises: store, progression: store, clock: { fixedNow })
        await model.load()
        model.start()
        await model.add(exerciseID: bench.id)
        let exercise = try #require(model.exercises.first)
        return try #require(exercise.summary(format: format).reasons.first)
    }

    @Test func topOfTheRangeSaysToAddLoadAndRestartTheReps() async throws {
        let reason = try await firstReason(history: [
            session(daysAgo: 6, weight: 60, reps: [11, 11, 11]),
            session(daysAgo: 3, weight: 60, reps: [12, 12, 12]),
        ])
        #expect(reason.hasPrefix("Today: go up to 62.5 kg and start again at 8 reps. Last time every set reached 12."))
    }

    @Test func insideTheRangeSaysWhichRepsToTryAndWhenLoadGoesUp() async throws {
        let reason = try await firstReason(history: [
            session(daysAgo: 6, weight: 60, reps: [8, 8, 8]),
            session(daysAgo: 3, weight: 60, reps: [9, 9, 8]),
        ])
        #expect(reason.hasPrefix(
            "Today: try 10/10/9 reps with 60 kg. When every set reaches 12 reps, the weight goes up."
        ))
    }

    @Test func twiceBelowTheRangeSaysToDropTheWeight() async throws {
        let history = [
            session(daysAgo: 6, weight: 75, reps: [8, 7, 7]),
            session(daysAgo: 3, weight: 75, reps: [8, 7, 6]),
        ]
        let reason = try await firstReason(history: history)
        #expect(reason.hasPrefix(
            "Today: drop to 72.5 kg and aim for 8 reps. The last two times, some sets fell short of 8 with the "
                + "previous weight."
        ))
    }

    @Test func withoutHistoryItExplainsHowToChooseTheWeight() async throws {
        let reason = try await firstReason(history: [])
        #expect(reason.hasPrefix("First time: choose a weight for 8 reps that leaves about"))
    }

    @Test func everyInstructionKeepsItsEvidenceLevel() async throws {
        let reason = try await firstReason(history: [session(daysAgo: 3, weight: 60, reps: [10, 10, 10])])
        #expect(reason.hasSuffix("evidence)") || reason.hasSuffix("heuristic)"))
    }
}
