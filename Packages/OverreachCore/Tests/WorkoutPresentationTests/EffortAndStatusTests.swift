import Analytics
import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import WorkoutPresentation

@MainActor
@Suite("Effort scale, status explanations and unfinished exercises")
struct EffortAndStatusTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
    private let row = Exercise(name: "Row", primaryMuscles: [.back], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func session(daysAgo: Double, weight: Double, reps: [Int]) -> StrengthSession {
        StrengthSession(
            name: "Push",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: 8) })]
        )
    }

    private func makeModel(history: [StrengthSession] = []) async -> (WorkoutModel, TestStore) {
        let store = TestStore(exercises: [bench, row], sessions: history)
        let fixedNow = now
        let model = WorkoutModel(
            workouts: store, exercises: store, progression: store, profiles: store, clock: { fixedNow }
        )
        await model.load()
        model.start()
        return (model, store)
    }

    // MARK: Effort scale

    @Test func repsInReserveChangesHowTargetsReadAndIsRemembered() async throws {
        let (model, store) = await makeModel(history: [session(daysAgo: 3, weight: 60, reps: [9, 9, 9])])
        await model.add(exerciseID: bench.id)
        #expect(try #require(model.exercises.first).summary(format: format).targetLine.hasSuffix("@ RPE 8"))
        // Adding reps before load: a reading on load vs rep progression.
        #expect(try #require(model.exercises.first).summary(format: format).readings.contains {
            $0.url.absoluteString.contains("peerj.com/articles/14142")
        })

        await model.setEffortScale(.repsInReserve)

        #expect(model.showsRepsInReserve)
        #expect(try #require(model.exercises.first).summary(format: format).targetLine.hasSuffix("@ RIR 2"))
        #expect(try await store.profile().effortScale == .repsInReserve)

        let fresh = WorkoutModel(workouts: store, exercises: store, progression: store, profiles: store)
        await fresh.load()
        #expect(fresh.effortScale == .repsInReserve)
    }

    @Test func effortTextConvertsRPEToRepsInReserve() {
        #expect(EffortScale.rpe.text(rpe: 8.5, format: format) == "RPE 8.5")
        #expect(EffortScale.repsInReserve.text(rpe: 8.5, format: format) == "RIR 1.5")
        #expect(EffortScale.repsInReserve.text(rpe: 10, format: format) == "RIR 0")
    }

    @Test func profilesWithoutAScaleLogRPE() throws {
        let old = Data(#"{"cycleTracking":"off","declaredBlocks":[]}"#.utf8)
        #expect(try JSONDecoder().decode(AthleteProfile.self, from: old).effortScale == .rpe)
    }

    // MARK: Status explanations

    @Test func aStallExplainsItsNumbersAndEvidence() async throws {
        // Six sessions at 60 × 10, then three where the target (more reps) was missed.
        let history = (0..<6).map { session(daysAgo: Double(30 - $0 * 3), weight: 60, reps: [10, 10, 10]) }
            + (0..<3).map { session(daysAgo: Double(9 - $0 * 3), weight: 60, reps: [10, 10, 9]) }
        let (model, _) = await makeModel(history: history)
        await model.add(exerciseID: bench.id)

        let summary = try #require(model.exercises.first).summary(format: format)
        #expect(summary.isStalled)
        let explanation = try #require(summary.statusExplanation)
        #expect(explanation.hasPrefix("Stalled: your best estimated 1RM in the last 3 sessions ("))
        #expect(explanation.contains("does not beat the 6 before ("))
        #expect(explanation.contains("you missed the target in 3 of them."))
        #expect(explanation.contains("Last time you were 1 rep short."))
        #expect(explanation.hasSuffix("(coaching heuristic)"))
        #expect(summary.stallSuggestions.allSatisfy { $0.contains(":") || $0.contains("then") })
    }

    @Test func progressIsExplainedToo() async throws {
        let history = (0..<6).map { session(daysAgo: Double(30 - $0 * 3), weight: 60, reps: [10, 10, 10]) }
            + (0..<3).map { session(daysAgo: Double(9 - $0 * 3), weight: 65, reps: [10, 10, 10]) }
        let (model, _) = await makeModel(history: history)
        await model.add(exerciseID: bench.id)
        let exercise = try #require(model.exercises.first)
        let explanation = try #require(exercise.summary(format: format).statusExplanation)
        #expect(explanation.hasPrefix("Progressing: your best estimated 1RM in the last 3 sessions"))
    }

    @Test func withoutEnoughHistoryThereIsNoExplanation() async throws {
        let (model, _) = await makeModel(history: [session(daysAgo: 3, weight: 60, reps: [10, 10, 10])])
        await model.add(exerciseID: bench.id)
        #expect(try #require(model.exercises.first).summary(format: format).statusExplanation == nil)
    }

    // MARK: Unfinished exercises

    @Test func finishingWithUnfinishedExercisesAsksFirst() async throws {
        let (model, store) = await makeModel()
        await model.add(exerciseID: bench.id)
        await model.add(exerciseID: row.id)
        let bench = model.exercises[0]
        model.setDone(true, set: bench.workingSets[0].id, in: bench.id)
        for set in model.exercises[1].workingSets {
            model.setDone(true, set: set.id, in: model.exercises[1].id)
        }

        #expect(model.unfinishedExerciseNames == ["Bench Press"])
        await model.requestFinish()
        #expect(model.isConfirmingUnfinished)
        #expect(model.isSessionActive)
        #expect(model.unfinishedExplanation.hasPrefix("Unfinished: Bench Press."))

        #expect(await model.finish(countingUnfinished: false))
        let saved = try #require(try await store.sessions(from: .distantPast, to: .distantFuture).first)
        #expect(saved.entries.map(\.countsForProgression) == [false, true])
        #expect(saved.entries.first?.sets.count == 1)
    }

    @Test func aCompleteSessionFinishesWithoutAsking() async {
        let (model, _) = await makeModel()
        await model.add(exerciseID: row.id)
        for set in model.exercises[0].workingSets {
            model.setDone(true, set: set.id, in: model.exercises[0].id)
        }
        await model.requestFinish()
        #expect(!model.isConfirmingUnfinished)
        #expect(!model.isSessionActive)
    }

    @Test func unfinishedEntriesDoNotMoveTheTargets() {
        let full = session(daysAgo: 6, weight: 60, reps: [10, 10, 10])
        var partial = session(daysAgo: 3, weight: 60, reps: [11])
        partial.entries[0].countsForProgression = false
        let exposures = ExerciseExposure.history(of: bench.id, in: [full, partial])
        #expect(exposures.count == 1)
        let target = ProgressionTargets.next(history: exposures, settings: ProgressionSettings(for: bench))
        #expect(target.sets.map(\.reps) == [11, 11, 11])
    }

    @Test func oldEntriesCount() throws {
        let json = #"{"id":"\#(UUID().uuidString)","exerciseID":"\#(UUID().uuidString)","sets":[]}"#
        #expect(try JSONDecoder().decode(ExerciseEntry.self, from: Data(json.utf8)).countsForProgression)
    }
}
