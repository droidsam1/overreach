import Domain
import Fixtures
import Foundation
import HistoryPresentation
import PresentationKit
import Testing

@MainActor
@Suite("HistoryModel")
struct HistoryModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func session(_ name: String, daysAgo: Double, sets: [WorkoutSet], focus: TrainingFocus? = nil) -> StrengthSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return StrengthSession(
            name: name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(exerciseID: squat.id, sets: sets)], focus: focus
        )
    }

    private func model(_ sessions: [StrengthSession]) async -> (HistoryModel, TestStore) {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let fixedNow = now
        let model = HistoryModel(workouts: store, exercises: store, routines: store, clock: { fixedNow })
        await model.load()
        return (model, store)
    }

    @Test func listsNewestFirstWithStats() async {
        let (model, _) = await model([
            session("Old", daysAgo: 5, sets: [WorkoutSet(weightKg: 100, reps: 5)]),
            session("New", daysAgo: 1, sets: [
                WorkoutSet(kind: .warmup, weightKg: 60, reps: 5),
                WorkoutSet(weightKg: 100, reps: 5),
                WorkoutSet(weightKg: 100, reps: 5),
            ]),
        ])

        #expect(model.summaries.map(\.title) == ["New", "Old"])
        let newest = model.summaries[0]
        #expect(newest.exerciseList == "Back Squat")
        #expect(newest.workingSets == 2)
        #expect(newest.statsLine(format: format).hasPrefix("2 sets · "))
        #expect(!model.showsEmptyState)
    }

    @Test func emptyStateOnlyWithoutSessions() async {
        let (model, _) = await model([])
        #expect(model.showsEmptyState)
    }

    @Test func detailDescribesSetsAndEstimatesOneRepMaxForWorkingSets() async throws {
        let squatSession = session("Lower", daysAgo: 1, sets: [
            WorkoutSet(kind: .warmup, weightKg: 60, reps: 5),
            WorkoutSet(weightKg: 100, reps: 5, rpe: 8),
        ], focus: .strength)
        let (model, _) = await model([squatSession])

        let detail = try #require(model.detail(for: squatSession.id, format: format))
        #expect(detail.focus == "Strength")
        #expect(detail.durationSeconds == 3_600)
        let sets = try #require(detail.entries.first).sets
        #expect(detail.entries.first?.name == "Back Squat")
        #expect(sets.map(\.number) == [1, 2])
        #expect(sets[0].text == "60 kg × 5 (warm-up)")
        #expect(sets[0].estimatedOneRepMax == nil)
        #expect(sets[1].text == "100 kg × 5 @ 8")
        #expect(sets[1].estimatedOneRepMax?.hasPrefix("e1RM ") == true)
    }

    @Test func deletingByOffsetsRemovesThoseSessions() async throws {
        let (model, store) = await model([
            session("A", daysAgo: 3, sets: [WorkoutSet(weightKg: 100, reps: 5)]),
            session("B", daysAgo: 2, sets: [WorkoutSet(weightKg: 100, reps: 5)]),
            session("C", daysAgo: 1, sets: [WorkoutSet(weightKg: 100, reps: 5)]),
        ])

        await model.delete(at: IndexSet([0, 2]))

        #expect(model.summaries.map(\.title) == ["B"])
        #expect(try await store.sessions(from: .distantPast, to: .distantFuture).map(\.name) == ["B"])
    }

    @Test func editorForAListedSessionOnly() async {
        let listed = session("Lower", daysAgo: 1, sets: [WorkoutSet(weightKg: 100, reps: 5)])
        let (model, _) = await model([listed])
        #expect(model.makeEditor(forSessionID: listed.id)?.draft == listed)
        #expect(model.makeEditor(forSessionID: UUID()) == nil)
        #expect(model.detail(for: UUID()) == nil)
    }
}

@MainActor
@Suite("SessionEditorModel screen state")
struct SessionEditorScreenStateTests {
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let row = Exercise(name: "Barbell Row", primaryMuscles: [.back], equipment: .barbell)

    private func editor() -> SessionEditorModel {
        let session = StrengthSession(
            name: "Lower",
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            entries: [
                ExerciseEntry(exerciseID: squat.id, sets: [WorkoutSet(weightKg: 100, reps: 5), WorkoutSet(weightKg: 100, reps: 5)]),
                ExerciseEntry(exerciseID: row.id, sets: [WorkoutSet(weightKg: 70, reps: 10)]),
            ]
        )
        return SessionEditorModel(session: session, catalog: [squat, row], workouts: TestStore())
    }

    @Test func issuesAreExplained() {
        let editor = editor()
        editor.draft.name = ""
        #expect(editor.issueMessages == ["Give the session a name."])
        #expect(!editor.canSave)
    }

    @Test func notesTextMapsEmptyToNoNotes() {
        let editor = editor()
        editor.notesText = "Felt heavy"
        #expect(editor.draft.notes == "Felt heavy")
        editor.notesText = ""
        #expect(editor.draft.notes == nil)
    }

    @Test func endTimeDefaultsToOneHourAfterStart() {
        let editor = editor()
        editor.addEndTime()
        #expect(editor.draft.endedAt == editor.draft.startedAt.addingTimeInterval(3_600))
    }

    @Test func moveAvailabilityAndSetNumbers() throws {
        let editor = editor()
        let first = try #require(editor.draft.entries.first)
        let last = try #require(editor.draft.entries.last)
        #expect(!editor.canMoveUp(first.id))
        #expect(editor.canMoveDown(first.id))
        #expect(!editor.canMoveDown(last.id))
        #expect(first.sets.map { editor.number(of: $0.id, in: first.id) } == [1, 2])
    }

    @Test func exercisesAreAddedAndReplacedByID() throws {
        let editor = editor()
        editor.addExercise(id: row.id)
        #expect(editor.draft.entries.last?.exerciseID == row.id)

        let first = try #require(editor.draft.entries.first)
        editor.replaceExercise(of: first.id, withID: row.id)
        #expect(editor.draft.entries.first?.exerciseID == row.id)
        #expect(editor.draft.entries.first?.sets == first.sets)

        editor.addExercise(id: UUID())
        #expect(editor.draft.entries.count == 3)
    }

    @Test func optionsCoverEveryFocusAndSetKind() {
        let editor = editor()
        #expect(editor.focusOptions.map(\.value) == TrainingFocus.allCases)
        #expect(editor.setKindOptions.map(\.value) == SetKind.allCases)
        #expect(SetKind.working.badge == nil)
        #expect(SetKind.warmup.badge == "W")
    }
}
