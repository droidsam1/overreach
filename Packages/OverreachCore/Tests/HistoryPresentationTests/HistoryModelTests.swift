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
        _ sessions: [StrengthSession], recordings: [RecordedStrengthActivity] = [],
        runSources: [any MetricsSource] = []
    ) async -> (HistoryModel, TestStore) {
        let store = TestStore(exercises: [squat], sessions: sessions)
        let fixedNow = now
        let model = HistoryModel(
            workouts: store, exercises: store, routines: store, runSources: runSources,
            recordedStrength: recordings.isEmpty ? nil : StrengthRecordings(activities: recordings),
            format: format, clock: { fixedNow }
        )
        await model.load()
        return (model, store)
    }

    @Test func runMatchChoicesUpdateCalendarAndListAndRestoreOnRelaunch() async throws {
        let day = CalendarDay(year: 2026, month: 11, day: 10)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let start = day.startDate(in: calendar).addingTimeInterval(3_600)
        let fixedNow = start.addingTimeInterval(7_200)
        let watch = RunActivity(
            id: "g", source: .garmin, startedAt: start, durationSeconds: 1_800, distanceMeters: 5_000
        )
        let copy = RunActivity(
            id: "h", source: .appleHealth, startedAt: start, durationSeconds: 1_800, distanceMeters: 5_000
        )
        let store = TestStore()
        var saved: [RunMatchPair: RunMatchChoice] = [:]
        func launch() async -> HistoryModel {
            let model = HistoryModel(
                workouts: store, exercises: store, routines: store, runSources: [
                    TimelineRuns(kind: .garmin, activities: [watch]),
                    TimelineRuns(kind: .appleHealth, activities: [copy]),
                ],
                calendar: calendar, runChoices: saved, saveRunChoices: { saved = $0 }, clock: { fixedNow }
            )
            await model.load()
            await model.calendar.load()
            model.calendar.select(day)
            return model
        }

        let first = await launch()
        let pair = RunMatchPair(garminID: watch.id, appleHealthID: copy.id)
        #expect(first.rows.count == 1)
        first.chooseRunMatch(.separate, for: pair)
        #expect(first.rows.count == 2)
        #expect(first.calendar.selectedDetail?.runs.count == 2)

        let restored = await launch()
        #expect(restored.runReviews.first?.isSeparate == true)
        #expect(restored.calendar.runs.count == 2)
        restored.chooseRunMatch(.linked, for: pair)
        await restored.load()
        await restored.calendar.load()
        #expect(restored.rows.count == 1)
        #expect(restored.calendar.runs.count == 1)
        #expect(saved[pair] == .linked)
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

    @Test func filtersRetainOneRowForAMultiSourceRunOrStrengthSession() async throws {
        let logged = session("Lower", daysAgo: 2, sets: [])
        let matched = RecordedStrengthActivity(
            id: "paired", source: .garmin, startedAt: logged.startedAt, durationSeconds: 3_600
        )
        let start = now.addingTimeInterval(-86_400)
        let garmin = RunActivity(
            id: "g1", source: .garmin, startedAt: start, durationSeconds: 1_800, distanceMeters: 5_000,
            trainingLoad: 55
        )
        let health = RunActivity(
            id: "h1", source: .appleHealth, startedAt: start.addingTimeInterval(60), durationSeconds: 1_740,
            distanceMeters: 5_000, averageHeartRate: 147
        )
        let (model, _) = await model([logged], recordings: [matched], runSources: [
            TimelineRuns(kind: .appleHealth, activities: [health]),
            TimelineRuns(kind: .garmin, activities: [garmin]),
        ])

        #expect(model.rows.map(\.id) == [.run("garmin:g1"), .session(logged.id)])
        #expect(model.sourceOptions.map(\.value) == [.app, .appleHealth, .garmin])
        #expect(model.detail(for: logged.id)?.sourceText == "Overreach · Garmin")

        model.activityFilter = .running
        model.sourceFilter = .appleHealth // The Apple Health copy contributes even though Garmin is preferred.
        let row = try #require(model.rows.first)
        guard case let .run(run) = row else {
            Issue.record("Expected a run in History")
            return
        }
        #expect(run.sources == [.garmin, .appleHealth])
        #expect(run.heartRate == "147 bpm")
        #expect(run.trainingMetrics.map(\.value) == ["55"])
        #expect(model.rows.count == 1)

        model.activityFilter = .strength
        #expect(model.showsFilteredEmptyState)
        model.sourceFilter = .garmin
        #expect(model.rows.map(\.id) == [.session(logged.id)])
        model.clearFilters()
        #expect(!model.hasFilters)
        #expect(model.rows.count == 2)
    }

    @Test func aFailedRunSourceLeavesOtherActivitiesVisibleAndShowsAWarning() async {
        let strength = session("Strength", daysAgo: 3, sets: [])
        let run = RunActivity(
            id: "watch", source: .garmin, startedAt: now.addingTimeInterval(-60), durationSeconds: 10, distanceMeters: 20
        )
        let (model, _) = await model([strength], runSources: [
            TimelineRuns(kind: .appleHealth, activities: [], fails: true),
            TimelineRuns(kind: .garmin, activities: [run]),
        ])

        #expect(model.rows.map(\.id) == [.run("garmin:watch"), .session(strength.id)])
        #expect(model.runWarning?.contains("Apple Health") == true)
        #expect(!model.showsEmptyState)
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
@Suite("Logging a watch workout")
struct LogWatchWorkoutTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)

    @Test func aWatchOnlyWorkoutBecomesASessionWithTheWatchsTimes() async throws {
        let recording = RecordedStrengthActivity(
            id: "g1", source: .garmin, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 3_000,
            averageHeartRate: 118, trainingLoad: 45
        )
        let store = TestStore(exercises: [squat])
        let fixedNow = now
        let model = HistoryModel(
            workouts: store, exercises: store, routines: store,
            recordedStrength: StrengthRecordings(activities: [recording]), clock: { fixedNow }
        )
        await model.load()
        #expect(model.rows.map(\.id) == [.recording("g1")])
        #expect(model.makeEditor(forRecording: "missing") == nil)

        let editor = try #require(model.makeEditor(forRecording: "g1"))
        #expect(editor.draft.startedAt == recording.startedAt)
        #expect(editor.draft.endedAt == recording.endedAt)
        editor.addExercise(squat)
        editor.draft.entries[0].sets[0].weightKg = 100
        editor.draft.entries[0].sets[0].reps = 5
        let saved = try #require(await editor.save())
        model.didSave(saved)

        #expect(model.rows.map(\.id) == [.session(saved.id)])  // no longer a watch-only row
        #expect(model.detail(for: saved.id)?.recording?.id == "g1")  // the watch's data is on the session
    }

    @Test func strengthChoicesSurviveReloadAndKeepCalendarAndDetailInSync() async throws {
        let date = now.addingTimeInterval(-60 * 60)
        let sets = [WorkoutSet(weightKg: 100, reps: 5, rpe: 8)]
        let first = StrengthSession(
            name: "Upper", startedAt: date,
            entries: [ExerciseEntry(exerciseID: squat.id, sets: sets)], notes: "Keep this"
        )
        let second = StrengthSession(name: "Lower", startedAt: date)
        let recording = RecordedStrengthActivity(
            id: "g1", source: .garmin, startedAt: date, durationSeconds: 1_800, averageHeartRate: 120
        )
        let store = TestStore(exercises: [squat], sessions: [first, second])
        let fixedNow = now
        var saved: [StrengthMatchPair: StrengthMatchChoice] = [:]
        let initial = HistoryModel(
            workouts: store, exercises: store, routines: store,
            recordedStrength: StrengthRecordings(activities: [recording]),
            saveStrengthChoices: { saved = $0 }, clock: { fixedNow }
        )
        await initial.load()
        #expect(initial.strengthReviews.count == 2)
        let candidate = try #require(initial.strengthReviews.first { $0.id.sessionID == first.id })
        initial.chooseStrengthMatch(.linked, for: candidate.id)

        let restored = HistoryModel(
            workouts: store, exercises: store, routines: store,
            recordedStrength: StrengthRecordings(activities: [recording]),
            strengthChoices: saved, clock: { fixedNow }
        )
        await restored.load()
        await restored.calendar.load()
        restored.calendar.select(nil)
        restored.calendar.select(CalendarDay(date))
        #expect(restored.rows.count == 2)
        #expect(restored.detail(for: first.id)?.recording?.id == "g1")
        #expect(restored.calendar.selectedDetail?.recordings.isEmpty == true)

        var edited = first
        edited.startedAt = date.addingTimeInterval(-86_400)
        try await store.save(edited)
        restored.didSave(edited)
        #expect(restored.detail(for: first.id)?.recording?.id == "g1")

        restored.separateStrengthMatch(for: first.id)
        #expect(restored.rows.count == 3)
        #expect(restored.detail(for: first.id)?.recording == nil)
        #expect(restored.detail(for: first.id)?.notes == "Keep this")
        #expect(restored.session(id: first.id)?.entries.first?.sets == sets)
        #expect(restored.calendar.selectedDetail?.recordings.map(\.id) == ["g1"])

        restored.chooseStrengthMatch(.linked, for: candidate.id)
        await restored.delete(first.id)
        #expect(restored.detail(for: second.id)?.recording?.id == "g1")
    }

    @Test func garminAndItsAppleHealthCopyAreOneWatchWorkout() async {
        let garmin = RecordedStrengthActivity(
            id: "g1", source: .garmin, startedAt: now.addingTimeInterval(-86_400), durationSeconds: 3_000,
            trainingLoad: 45
        )
        let copy = RecordedStrengthActivity(
            id: "h1", source: .appleHealth, startedAt: now.addingTimeInterval(-86_400 + 30), durationSeconds: 2_950,
            averageHeartRate: 118
        )
        let combined = CombinedRecordedStrengthSource([
            StrengthRecordings(activities: [garmin]), StrengthRecordings(activities: [copy]),
        ])

        let recordings = await combined.strengthActivities(from: .distantPast, to: .distantFuture)

        #expect(recordings.map(\.id) == ["g1"])
        #expect(recordings.first?.averageHeartRate == 118)
    }
}

private struct TimelineRuns: MetricsSource {
    enum Failure: Error { case unavailable }
    let kind: DataSourceKind
    let activities: [RunActivity]
    var fails = false

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        if fails { throw Failure.unavailable }
        return activities.filter { (start...end).contains($0.startedAt) }
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
