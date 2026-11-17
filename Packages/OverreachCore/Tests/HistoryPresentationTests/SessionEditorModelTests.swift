import Domain
import Fixtures
import Foundation
import HistoryPresentation
import Testing

/// Records backups requested after saving.
private actor BackupSpy: BackupService {
    private(set) var backUps = 0

    func isConfigured() async -> Bool { true }
    func folderName() async -> String? { "Backups" }
    func configure(folder: URL) async throws {}
    func backUp(now: Date) async throws -> BackupSummary { throw CancellationError() }
    func backUpIfConfigured(now: Date) async -> Bool {
        backUps += 1
        return true
    }
    func exportData(now: Date) async throws -> Data { Data() }
    func latestBackup() async throws -> BackupDocument? { nil }
    func restore(from data: Data) async throws -> BackupSummary { throw CancellationError() }
    func hasUserData() async throws -> Bool { true }
}

/// A repository whose saves always fail.
private struct FailingWorkouts: WorkoutRepository {
    struct Failure: Error {}
    func sessions(from start: Date, to end: Date) async throws -> [StrengthSession] { [] }
    func save(_ session: StrengthSession) async throws { throw Failure() }
    func deleteSession(id: UUID) async throws { throw Failure() }
}

@MainActor
@Suite("SessionEditorModel")
struct SessionEditorModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let frontSquat = Exercise(name: "Front Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let row = Exercise(name: "Barbell Row", primaryMuscles: [.back], equipment: .barbell)

    private func lowerA() -> StrengthSession {
        let start = now.addingTimeInterval(-2 * 86_400)
        return StrengthSession(
            name: "Lower A",
            startedAt: start,
            endedAt: start.addingTimeInterval(4_200),
            entries: [
                ExerciseEntry(exerciseID: squat.id, sets: [
                    WorkoutSet(kind: .warmup, weightKg: 60, reps: 5, completedAt: start.addingTimeInterval(300)),
                    WorkoutSet(weightKg: 100, reps: 5, rpe: 8, completedAt: start.addingTimeInterval(900)),
                    WorkoutSet(weightKg: 100, reps: 5, rpe: 8.5, completedAt: start.addingTimeInterval(1_200)),
                ]),
                ExerciseEntry(exerciseID: row.id, sets: [
                    WorkoutSet(weightKg: 70, reps: 10, rpe: 8, completedAt: start.addingTimeInterval(2_400)),
                ]),
            ],
            focus: .strength
        )
    }

    private func makeEditor(
        _ session: StrengthSession,
        backup: BackupSpy? = nil
    ) -> (SessionEditorModel, TestStore) {
        let store = TestStore(exercises: [squat, frontSquat, row], sessions: [session])
        let fixedNow = now
        let editor = SessionEditorModel(
            session: session, catalog: [squat, frontSquat, row], workouts: store, backup: backup, clock: { fixedNow }
        )
        return (editor, store)
    }

    private func stored(_ store: TestStore) async throws -> [StrengthSession] {
        try await store.sessions(from: .distantPast, to: .distantFuture)
    }

    @Test func startsWithoutChangesAndCannotSave() async {
        let (editor, _) = makeEditor(lowerA())

        #expect(!editor.hasChanges)
        #expect(!editor.canSave)
        #expect(await editor.save() == nil)
    }

    @Test func savesCorrectedValuesOverTheSameSession() async throws {
        let session = lowerA()
        let backup = BackupSpy()
        let (editor, store) = makeEditor(session, backup: backup)
        editor.draft.name = "Lower A (heavy)"
        editor.draft.notes = "Belt on top sets"
        editor.draft.focus = .mixed
        editor.draft.entries[0].sets[2].weightKg = 102.5  // typo fixed
        editor.draft.entries[0].sets[2].kind = .failure

        let saved = try #require(await editor.save())

        #expect(saved.id == session.id)
        let sessions = try await stored(store)
        #expect(sessions.count == 1)
        #expect(sessions.first == saved)
        #expect(saved.name == "Lower A (heavy)")
        #expect(saved.notes == "Belt on top sets")
        #expect(saved.focus == .mixed)
        #expect(saved.entries[0].sets[2].weightKg == 102.5)
        #expect(saved.entries[0].sets[2].kind == .failure)
        #expect(await backup.backUps == 1)
    }

    @Test func movingTheStartKeepsTheDuration() async throws {
        let session = lowerA()
        let (editor, store) = makeEditor(session)
        let dayEarlier = session.startedAt.addingTimeInterval(-86_400)

        editor.moveStart(to: dayEarlier)
        _ = try #require(await editor.save())

        let saved = try #require(try await stored(store).first)
        #expect(saved.startedAt == dayEarlier)
        #expect(saved.durationSeconds == session.durationSeconds)
        #expect(saved.entries[0].sets[1].completedAt == dayEarlier.addingTimeInterval(900))
    }

    @Test func addsSetsCopyingTheLastAndRemovesSets() {
        let (editor, _) = makeEditor(lowerA())
        let squatEntry = editor.draft.entries[0]

        editor.addSet(to: squatEntry.id)
        let added = editor.draft.entries[0].sets.last
        #expect(editor.draft.entries[0].sets.count == 4)
        #expect(added?.weightKg == 100)
        #expect(added?.reps == 5)
        #expect(added?.rpe == 8.5)
        #expect(added?.kind == .working)

        editor.removeSet(squatEntry.sets[0].id, from: squatEntry.id)
        #expect(editor.draft.entries[0].sets.count == 3)
        #expect(editor.draft.entries[0].sets.allSatisfy { $0.kind == .working })
    }

    @Test func addsReplacesReordersAndRemovesExercises() {
        let (editor, _) = makeEditor(lowerA())
        let squatEntryID = editor.draft.entries[0].id
        let rowEntryID = editor.draft.entries[1].id

        editor.replaceExercise(of: squatEntryID, with: frontSquat)
        #expect(editor.draft.entries[0].exerciseID == frontSquat.id)
        #expect(editor.draft.entries[0].sets.count == 3)
        #expect(editor.name(of: editor.draft.entries[0].exerciseID) == "Front Squat")

        editor.moveExercise(rowEntryID, by: -1)
        #expect(editor.draft.entries.map(\.id) == [rowEntryID, squatEntryID])
        editor.moveExercise(rowEntryID, by: -1)  // already first
        #expect(editor.draft.entries.map(\.id) == [rowEntryID, squatEntryID])

        editor.addExercise(squat)
        #expect(editor.draft.entries.count == 3)
        #expect(editor.draft.entries.last?.exerciseID == squat.id)

        editor.removeExercise(rowEntryID)
        #expect(!editor.draft.entries.contains { $0.id == rowEntryID })
    }

    @Test func dropsEmptySetsAndExercisesOnSave() async throws {
        let (editor, store) = makeEditor(lowerA())
        editor.addExercise(frontSquat)  // starts with one empty set
        editor.addSet(to: editor.draft.entries[2].id)  // copies the empty set
        editor.addSet(to: editor.draft.entries[1].id)
        editor.draft.entries[1].sets[1].weightKg = nil  // values cleared, RPE alone is not a set
        editor.draft.entries[1].sets[1].reps = nil

        _ = try #require(await editor.save())

        let saved = try #require(try await stored(store).first)
        #expect(saved.entries.map(\.exerciseID) == [squat.id, row.id])
        #expect(saved.entries[1].sets.count == 1)
    }

    @Test func refusesToSaveASessionWithoutSets() async throws {
        let session = lowerA()
        let (editor, store) = makeEditor(session)
        for entry in editor.draft.entries { editor.removeExercise(entry.id) }

        #expect(editor.issues == [.noSets])
        #expect(!editor.canSave)
        #expect(await editor.save() == nil)
        #expect(try await stored(store) == [session])
    }

    @Test func refusesToSaveWhenTheEndIsBeforeTheStart() {
        let (editor, _) = makeEditor(lowerA())

        editor.setEnd(editor.draft.startedAt.addingTimeInterval(-60))

        #expect(editor.issues == [.endsBeforeStart])
        #expect(!editor.canSave)
    }

    @Test func keepsTheDraftWhenSavingFails() async {
        let session = lowerA()
        let editor = SessionEditorModel(session: session, catalog: [squat, row], workouts: FailingWorkouts())
        editor.draft.name = "Lower B"

        #expect(await editor.save() == nil)
        #expect(editor.errorMessage != nil)
        #expect(editor.draft.name == "Lower B")
        #expect(editor.hasChanges)
    }
}

@MainActor
@Suite("HistoryModel editing")
struct HistoryModelEditingTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func session(_ name: String, daysAgo: Double) -> StrengthSession {
        StrengthSession(
            name: name,
            startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: [WorkoutSet(weightKg: 60, reps: 8)])]
        )
    }

    @Test func savedEditsUpdateTheListInDateOrder() async throws {
        let sessions = [session("Push A", daysAgo: 6), session("Push B", daysAgo: 4), session("Push C", daysAgo: 2)]
        let store = TestStore(exercises: [bench], sessions: sessions)
        let fixedNow = now
        let history = HistoryModel(workouts: store, exercises: store, clock: { fixedNow })
        await history.load()
        #expect(history.summaries.map(\.session.name) == ["Push C", "Push B", "Push A"])

        let editor = history.makeEditor(for: try #require(history.session(id: sessions[0].id)))
        editor.draft.name = "Push A (moved)"
        editor.moveStart(to: now.addingTimeInterval(-86_400))
        editor.draft.entries[0].sets[0].reps = 10
        history.didSave(try #require(await editor.save()))

        #expect(history.summaries.map(\.session.name) == ["Push A (moved)", "Push C", "Push B"])
        #expect(history.summaries.first?.tonnageKg == 600)
        #expect(history.session(id: sessions[0].id)?.name == "Push A (moved)")
    }
}
