import Analytics
import Domain
import Foundation
import Testing

@Suite("Lift status")
struct LiftStatusTests {
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(
        _ day: Int, _ weight: Double, _ reps: [Int], counts: Bool = true, routine: Routine? = nil
    ) -> StrengthSession {
        let date = start.addingTimeInterval(Double(day) * 86_400)
        let sets = reps.map { WorkoutSet(weightKg: weight, reps: $0) }
        return StrengthSession(
            name: "Legs", startedAt: date, endedAt: date.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: sets, countsForProgression: counts)],
            routineID: routine?.id
        )
    }

    @Test func unfinishedExercisesAreLeftOutAsInTheLogger() throws {
        let sessions = [session(0, 100, [5, 5, 5]), session(3, 60, [2], counts: false), session(6, 102.5, [5, 5, 5])]

        let status = try #require(LiftStatus.assessAll(
            index: ExposureIndex(sessions: sessions), exercises: [squat.id: squat], stored: [:], routines: [],
            now: start.addingTimeInterval(6 * 86_400)
        ).first)

        #expect(status.history == ExerciseExposure.history(of: squat.id, in: sessions))
        #expect(status.history.count == 2)
    }

    @Test func theLatestSessionsRoutinePrescriptionSetsTheSettings() throws {
        let scheme = ProgressionScheme.doubleProgression(sets: 3, minReps: 8, maxReps: 12, targetRPE: 8)
        let routine = Routine(
            name: "Legs", exerciseIDs: [squat.id],
            prescriptions: [RoutinePrescription(exerciseID: squat.id, scheme: scheme)]
        )
        let sessions = [session(0, 80, [10, 10, 10]), session(3, 80, [11, 10, 10], routine: routine)]

        let status = try #require(LiftStatus.assessAll(
            index: ExposureIndex(sessions: sessions), exercises: [squat.id: squat], stored: [:], routines: [routine],
            now: start.addingTimeInterval(3 * 86_400)
        ).first)

        #expect(status.settings == ProgressionTargets.settings(for: squat, stored: nil, prescription: scheme))
        #expect(status.settings.scheme == scheme)
    }

    @Test func anExerciseMissingFromTheCatalogUsesTheSameFallbackEverywhere() {
        let settings = ProgressionTargets.settings(for: nil, stored: nil)
        #expect(settings == ProgressionSettings(incrementKg: 2.5))
    }
}
