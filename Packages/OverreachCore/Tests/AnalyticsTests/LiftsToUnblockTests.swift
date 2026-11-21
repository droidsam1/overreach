@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Lifts to unblock")
struct LiftsToUnblockTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let linear = ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5)

    private func session(_ daysAgo: Int, _ weight: Double, _ reps: [Int], routine: UUID? = nil) -> StrengthSession {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return StrengthSession(
            name: "Lower", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0) })],
            routineID: routine
        )
    }

    /// Three missed targets at 102.5 kg; `lastReps` decides how far the last miss was.
    /// Three missed targets at 102.5 kg; `lastReps` decides how far the last miss was.
    private func stalledSessions(
        ago offset: Int = 0, lastReps: [Int] = [4, 3, 3], routine: UUID? = nil
    ) -> [StrengthSession] {
        let days = [19, 16, 13, 10, 7, 4].map { $0 + offset }
        let weights = [95, 97.5, 100, 102.5, 102.5, 102.5]
        let reps = [[5, 5, 5], [5, 5, 5], [5, 5, 5], [4, 4, 4], [4, 4, 3], lastReps]
        return days.indices.map { session(days[$0], weights[$0], reps[$0], routine: routine) }
    }

    private func find(
        _ sessions: [StrengthSession], stored: ProgressionSettings? = nil, routines: [Routine] = []
    ) -> [StalledLift] {
        LiftsToUnblock.find(
            index: ExposureIndex(sessions: sessions), exercises: [squat.id: squat],
            stored: stored.map { [squat.id: $0] } ?? [:], routines: routines, currentExerciseIDs: nil, now: now
        )
    }

    @Test func aStalledLiftHasItsStartBestSetAndNextStep() throws {
        let lift = try #require(find(stalledSessions(), stored: linear).first)
        #expect(lift.exerciseID == squat.id)
        #expect(lift.explanation.stalledSince == now.addingTimeInterval(-10 * 86_400))
        #expect(lift.explanation.bestSet.weightKg == 102.5)
        #expect(lift.explanation.bestSet.reps == 4)
        #expect(lift.nextStep == .switchToDoubleProgression)
        #expect(!lift.schemeFromRoutine)
    }

    @Test func aLiftNotTrainedIn28DaysIsNotListed() {
        #expect(find(stalledSessions(ago: 25), stored: linear).isEmpty)
        #expect(find(stalledSessions(), stored: linear).count == 1)
    }

    @Test func switchingToARepRangeKeepsTheSetsAndStartsFromTheCurrentReps() throws {
        let lift = try #require(find(stalledSessions(), stored: linear).first)
        let changed = try #require(lift.applying(.switchToDoubleProgression))
        #expect(changed.scheme == .doubleProgression(sets: 3, minReps: 5, maxReps: 7, targetRPE: 8))
        #expect(changed.incrementKg == 2.5)
        #expect(lift.applying(.swapVariation(weeks: 3...4)) == nil)
        #expect(lift.applying(.deloadLift(loadReduction: 0.1)) == nil)
    }

    @Test func aOneRepMissMicroloadsWithHalfTheIncrement() throws {
        let lift = try #require(find(stalledSessions(lastReps: [4, 4, 4]), stored: linear).first)
        #expect(lift.nextStep == .microload(incrementKg: 1.25))
        let changed = try #require(lift.applying(.microload(incrementKg: 1.25)))
        #expect(changed.incrementKg == 1.25)
        #expect(changed.scheme == linear.scheme)
    }

    @Test func microloadingStopsAtOneKilogram() throws {
        var small = linear
        small.incrementKg = 1.25
        let lift = try #require(find(stalledSessions(lastReps: [4, 4, 4]), stored: small).first)
        #expect(lift.nextStep == .switchToDoubleProgression)
    }

    @Test func aRepRangeMovesHeavierWhenThereIsRoom() {
        let wide = ProgressionScheme.doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8)
        #expect(StallSuggestion.changeRepRange.scheme(replacing: wide)
            == .doubleProgression(sets: 3, minReps: 6, maxReps: 10, targetRPE: 8))
        let low = ProgressionScheme.doubleProgression(sets: 4, minReps: 3, maxReps: 5, targetRPE: 8)
        #expect(StallSuggestion.changeRepRange.scheme(replacing: low)
            == .doubleProgression(sets: 4, minReps: 5, maxReps: 7, targetRPE: 8))
        #expect(StallSuggestion.changeRepRange.scheme(replacing: linear.scheme) == nil)
    }

    @Test func aRoutinePrescriptionKeepsSchemeChangesInTheRoutine() throws {
        let routine = Routine(
            name: "Lower", exerciseIDs: [squat.id],
            prescriptions: [RoutinePrescription(exerciseID: squat.id, scheme: linear.scheme)]
        )
        let lift = try #require(find(stalledSessions(routine: routine.id), routines: [routine]).first)
        #expect(lift.schemeFromRoutine)
        #expect(lift.nextStep == .switchToDoubleProgression)
        #expect(lift.applying(.switchToDoubleProgression) == nil)
        #expect(lift.applying(.microload(incrementKg: 1.25))?.incrementKg == 1.25)
    }
}
