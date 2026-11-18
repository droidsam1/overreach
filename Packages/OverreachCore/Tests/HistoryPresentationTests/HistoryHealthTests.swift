import Domain
import Fixtures
import Foundation
import HistoryPresentation
import Testing

@MainActor
@Suite("History and Apple Health")
struct HistoryHealthTests {
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(source: DataSourceKind = .app) -> StrengthSession {
        StrengthSession(
            name: "Lower", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 100, reps: 5)])],
            source: source
        )
    }

    private func editor(_ session: StrengthSession, health: RecordingHealthWriter) -> SessionEditorModel {
        let store = TestStore(exercises: [squat], sessions: [session])
        return SessionEditorModel(session: session, catalog: [squat], workouts: store, health: health)
    }

    @Test func changingTheTimesRewritesTheWorkout() async throws {
        let health = RecordingHealthWriter()
        let editor = editor(session(), health: health)
        editor.setEnd(start.addingTimeInterval(1_800))

        let saved = try #require(await editor.save())

        #expect(await health.saved == [saved])
        #expect(await health.deleted.isEmpty)
    }

    @Test func otherEditsLeaveTheWorkoutAlone() async {
        let health = RecordingHealthWriter()
        let editor = editor(session(), health: health)
        editor.draft.name = "Legs"

        #expect(await editor.save() != nil)

        #expect(await health.saved.isEmpty)
        #expect(await health.deleted.isEmpty)
    }

    @Test func removingTheEndTimeRemovesTheWorkout() async {
        let health = RecordingHealthWriter()
        let session = session()
        let editor = editor(session, health: health)
        editor.setEnd(nil)

        #expect(await editor.save() != nil)

        #expect(await health.saved.isEmpty)
        #expect(await health.deleted == [session.id])
    }

    @Test func importedSessionsAreNotWritten() async {
        let health = RecordingHealthWriter()
        let editor = editor(session(source: .strongImport), health: health)
        editor.setEnd(start.addingTimeInterval(1_800))

        #expect(await editor.save() != nil)

        #expect(await health.saved.isEmpty)
    }

    @Test func aHealthFailureKeepsTheEdit() async {
        let editor = editor(session(), health: RecordingHealthWriter(failing: true))
        editor.setEnd(start.addingTimeInterval(1_800))

        #expect(await editor.save() != nil)
        #expect(editor.errorMessage == nil)
    }

    @Test func deletingASessionRemovesItsWorkout() async {
        let health = RecordingHealthWriter()
        let session = session()
        let store = TestStore(exercises: [squat], sessions: [session])
        let model = HistoryModel(workouts: store, exercises: store, routines: store, health: health)

        await model.delete(session.id)

        #expect(await health.deleted == [session.id])
    }

    @Test func aFailedDeleteLeavesTheWorkout() async {
        let health = RecordingHealthWriter()
        let session = session()
        let store = TestStore(exercises: [squat], sessions: [session])
        await store.setFailing(true)
        let model = HistoryModel(workouts: store, exercises: store, routines: store, health: health)

        await model.delete(session.id)

        #expect(await health.deleted.isEmpty)
    }
}
