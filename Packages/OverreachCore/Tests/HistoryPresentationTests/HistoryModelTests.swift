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

    private func model(
        _ sessions: [StrengthSession], recordings: [RecordedStrengthActivity] = []
    ) async -> (HistoryModel, TestStore) {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let fixedNow = now
        let model = HistoryModel(
            workouts: store, exercises: store, routines: store,
            recordedStrength: recordings.isEmpty ? nil : StrengthRecordings(activities: recordings),
            format: format, clock: { fixedNow }
        )
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

    @Test func matchedWatchMetricsEnrichTheDetailAndUnmatchedWorkoutsAppearInOrder() async throws {
        let logged = session("Lower", daysAgo: 2, sets: [WorkoutSet(weightKg: 100, reps: 5)])
        let older = session("Upper", daysAgo: 4, sets: [])
        let matched = RecordedStrengthActivity(
            id: "matched", source: .garmin, startedAt: logged.startedAt.addingTimeInterval(-5 * 60),
            durationSeconds: 4_200, averageHeartRate: 125, trainingLoad: 42.5, aerobicTrainingEffect: 2.5,
            totalSets: 20, totalReps: 100
        )
        let watchOnly = RecordedStrengthActivity(
            id: "watch-only", source: .garmin, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800
        )
        let (model, store) = await model([older, logged], recordings: [matched, watchOnly])

        #expect(model.rows.map(\.id) == [.recording(watchOnly.id), .session(logged.id), .session(older.id)])
        let detail = try #require(model.detail(for: logged.id, format: format))
        #expect(detail.recording?.source == "Garmin")
        #expect(detail.recording?.metrics.map(\.value) == ["125 bpm", "42.5", "2.5"])
        #expect(detail.entries.first?.sets.map(\.text) == ["100 kg × 5"])
        #expect(detail.durationSeconds == 3_600)
        #expect(model.detail(for: older.id)?.recording == nil)
        #expect(await store.sessions(from: .distantPast, to: .distantFuture) == [older, logged])
    }

    @Test func watchOnlyWorkoutPreventsTheEmptyStateAndRematchesAfterAnEditOrDeletion() async throws {
        let logged = session("Lower", daysAgo: 2, sets: [])
        let recording = RecordedStrengthActivity(
            id: "watch", source: .garmin, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 1_800
        )
        let (model, _) = await model([], recordings: [recording])
        #expect(!model.showsEmptyState)
        #expect(model.rows.map(\.id) == [.recording(recording.id)])

        model.didSave(logged)
        #expect(model.rows.map(\.id) == [.recording(recording.id), .session(logged.id)])
        var edited = logged
        edited.startedAt = recording.startedAt
        edited.endedAt = recording.endedAt
        model.didSave(edited)
        #expect(model.rows.map(\.id) == [.session(logged.id)])
        #expect(model.detail(for: logged.id)?.recording?.id == recording.id)

        await model.delete(logged.id)
        #expect(model.rows.map(\.id) == [.recording(recording.id)])
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

private struct StrengthRecordings: RecordedStrengthSource {
    let activities: [RecordedStrengthActivity]

    func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] {
        activities.filter { $0.startedAt >= start && $0.startedAt <= end }
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
