import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

@MainActor
@Suite("Lifts to unblock in Plan")
struct LiftsToUnblockRowTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let linear = ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func session(_ daysAgo: Int, _ weight: Double, _ reps: [Int]) -> StrengthSession {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return StrengthSession(
            name: "Lower", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0) })]
        )
    }

    private func model(ago offset: Int = 0, lastReps: [Int] = [4, 3, 3]) async throws -> (PlanModel, TestStore) {
        let sessions = [
            session(19 + offset, 95, [5, 5, 5]), session(16 + offset, 97.5, [5, 5, 5]),
            session(13 + offset, 100, [5, 5, 5]), session(10 + offset, 102.5, [4, 4, 4]),
            session(7 + offset, 102.5, [4, 4, 3]), session(4 + offset, 102.5, lastReps),
        ]
        let store = TestStore(exercises: [squat], sessions: sessions)
        try await store.save(linear, for: squat.id)
        let fixedNow = now
        let model = PlanModel(
            profiles: store, workouts: store, exercises: store, progression: store, routines: store,
            clock: { fixedNow }, calendar: calendar
        )
        await model.load()
        return (model, store)
    }

    @Test func aStalledLiftNamesItsDateBestSetAndOneNextStep() async throws {
        let (model, _) = try await model()
        let row = try #require(model.liftsToUnblockRows.first)
        let stalledSince = now.addingTimeInterval(-10 * 86_400).formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        )
        #expect(row.name == "Back Squat")
        #expect(row.since == "No progress since \(stalledSince) (best 102.5 kg × 4)")
        #expect(row.nextStep?.text.hasPrefix("Switch to a rep range") == true)
        #expect(row.nextStep?.evidence.isEmpty == false)
        #expect(row.otherSteps.count >= 2)
        #expect(row.change?.title == "Switch to 5–7 reps")
        #expect(row.change?.confirmation
            == "Back Squat will use 3 sets of 5–7 reps from its next session, adding reps before load.")
        #expect(row.note == nil)
    }

    @Test func aLiftNotTrainedIn28DaysHasNoRow() async throws {
        let (model, _) = try await model(ago: 25)
        #expect(model.liftsToUnblockRows.isEmpty)
    }

    @Test func applyingTheNextStepSavesTheExerciseSettings() async throws {
        let (model, store) = try await model(lastReps: [4, 4, 4])
        let row = try #require(model.liftsToUnblockRows.first)
        #expect(row.change?.title == "Use 1.25 kg jumps")

        await model.applyNextStep(for: row.id)
        let saved = try await store.progressionSettings(for: squat.id)
        #expect(saved?.incrementKg == 1.25)
        #expect(saved?.scheme == linear.scheme)
        let applied = try #require(model.liftsToUnblockRows.first)
        #expect(applied.change == nil)
        #expect(applied.note == "Changed. Give it three sessions before judging it.")
    }

    @Test func aFailedSaveKeepsTheChangeOnOffer() async throws {
        let (model, store) = try await model()
        await store.setFailing(true)
        await model.applyNextStep(for: squat.id)
        #expect(model.errorMessage == "Could not save the exercise settings. Try again.")
        #expect(model.liftsToUnblockRows.first?.change != nil)
        #expect(try await store.progressionSettings(for: squat.id) == linear)
    }
}
