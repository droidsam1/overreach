import Domain
import Fixtures
import Foundation
import Testing
import WorkoutPresentation

@MainActor
private final class DraftStore: WorkoutDraftStore {
    var data: Data?
    var refusesWrites = false
    var refusesRemoval = false

    func readDraft() -> Data? { data }

    func writeDraft(_ data: Data?) throws {
        if refusesWrites || (data == nil && refusesRemoval) { throw DraftFailure.unavailable }
        self.data = data
    }
}

private enum DraftFailure: Error {
    case unavailable
}

private actor FailingWorkoutRepository: WorkoutRepository {
    var refusesSave = true
    private var saved: [StrengthSession] = []

    func allowSaving() { refusesSave = false }

    func sessions(from start: Date, to end: Date) -> [StrengthSession] {
        saved.filter { (start...end).contains($0.startedAt) }
    }

    func save(_ session: StrengthSession) throws {
        if refusesSave { throw DraftFailure.unavailable }
        saved.append(session)
    }

    func deleteSession(id: UUID) {
        saved.removeAll { $0.id == id }
    }
}

@MainActor
@Suite("Workout draft recovery")
struct WorkoutDraftTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    private func model(
        store: TestStore, draft: DraftStore, at date: Date, workouts: (any WorkoutRepository)? = nil,
        alerts: (any RestAlertScheduler)? = nil
    ) -> WorkoutModel {
        WorkoutModel(
            workouts: workouts ?? store, exercises: store, progression: store, restAlerts: alerts,
            draftStore: draft, clock: { date }
        )
    }

    @Test func aRelaunchPreservesTheRoutineEditsNotesAndAdjustedRest() async throws {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let first = model(store: store, draft: draft, at: now)
        let routine = Routine(name: "Push A", focus: .strength, exerciseIDs: [bench.id])
        await first.start(routine)

        let exerciseID = first.exercises[0].id
        first.exercises[0].sets[0].weightKg = 52.5
        first.exercises[0].sets[0].reps = 4
        first.exercises[0].sets[0].rpe = 8
        first.setDone(true, set: first.exercises[0].sets[0].id, in: exerciseID)
        first.rest.addTime()
        first.exercises[0].sets[1].weightKg = 55
        first.exercises[0].notes = "  Used the new bench.  "
        first.sessionNotes = "  Felt strong.  "
        await first.setEffortScale(.repsInReserve)
        let expectedExercises = first.exercises
        let reopenedAt = now.addingTimeInterval(35)
        let expectedRest = first.rest.state(at: reopenedAt)
        #expect(await store.sessions(from: .distantPast, to: .distantFuture).isEmpty)

        let reopened = model(store: store, draft: draft, at: reopenedAt)
        #expect(reopened.canResumeWorkout)
        #expect(!reopened.isSessionActive)
        #expect(reopened.recoverableWorkoutName == "Push A")
        reopened.start(name: "Can't replace a pending draft")
        #expect(!reopened.isSessionActive)

        await reopened.resumeSavedWorkout()
        #expect(!reopened.needsDraftRecovery)
        #expect(reopened.startedAt == now)
        #expect(reopened.sessionRoutine == routine)
        #expect(reopened.sessionFocus == .strength)
        #expect(reopened.sessionNotes == "  Felt strong.  ")
        #expect(reopened.exercises == expectedExercises)
        #expect(reopened.showsRepsInReserve)
        #expect(reopened.rest.state(at: reopenedAt) == expectedRest)

        #expect(await reopened.finish(countingUnfinished: false))
        let saved = await store.sessions(from: .distantPast, to: .distantFuture)
        let session = try #require(saved.first)
        #expect(saved.count == 1)
        #expect(session.startedAt == now)
        #expect(session.notes == "Felt strong.")
        #expect(session.routineID == routine.id)
        #expect(session.entries.first?.notes == "Used the new bench.")
        #expect(session.entries.first?.sets.map(\.weightKg) == [52.5])
        #expect(session.entries.first?.countsForProgression == false)
        #expect(draft.data == nil)
    }

    @Test func failedCommitKeepsTheDraftAvailableForAnotherLaunch() async throws {
        let store = TestStore(exercises: [bench])
        let workouts = FailingWorkoutRepository()
        let draft = DraftStore()
        let first = model(store: store, draft: draft, at: now, workouts: workouts)
        first.start()
        await first.add(bench)
        first.exercises[0].sets[0].weightKg = 50
        first.exercises[0].sets[0].isDone = true

        #expect(await !first.finish())
        #expect(first.isSessionActive)
        #expect(draft.data != nil)

        await workouts.allowSaving()
        let reopened = model(store: store, draft: draft, at: now, workouts: workouts)
        await reopened.resumeSavedWorkout()
        #expect(reopened.exercises[0].sets[0].weightKg == 50)
        #expect(await reopened.finish())
        #expect(await workouts.sessions(from: .distantPast, to: .distantFuture).count == 1)
    }

    @Test func aCommittedDraftLeftOnDiskDoesNotReopenOrDuplicateHistory() async throws {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let first = model(store: store, draft: draft, at: now)
        first.start()
        await first.add(bench)
        first.exercises[0].sets[0].isDone = true

        draft.refusesRemoval = true
        #expect(await first.finish())
        #expect(!first.isSessionActive)
        #expect(draft.data != nil)
        let saved = await store.sessions(from: .distantPast, to: .distantFuture)
        #expect(saved.count == 1)

        // Even if the finish time or date is corrected in History, the saved ID still matches.
        var corrected = try #require(saved.first)
        corrected.startedAt = now.addingTimeInterval(-300)
        try await store.save(corrected)

        draft.refusesRemoval = false
        let reopened = model(store: store, draft: draft, at: now.addingTimeInterval(60))
        await reopened.resumeSavedWorkout()
        #expect(!reopened.isSessionActive)
        #expect(!reopened.needsDraftRecovery)
        #expect(reopened.draftNotice != nil)
        #expect(draft.data == nil)
        #expect(await store.sessions(from: .distantPast, to: .distantFuture) == [corrected])
    }

    @Test func discardRemovesTheOnDiskDraftOnlyAfterSuccessfulCleanup() async {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let first = model(store: store, draft: draft, at: now)
        first.start()
        first.sessionNotes = "Remember this until discard succeeds"

        draft.refusesRemoval = true
        first.discard()
        #expect(first.isSessionActive)
        #expect(first.draftErrorMessage != nil)
        #expect(draft.data != nil)

        draft.refusesRemoval = false
        first.discard()
        #expect(!first.isSessionActive)
        #expect(draft.data == nil)
        #expect(!model(store: store, draft: draft, at: now).needsDraftRecovery)
    }

    @Test func discardingAfterRelaunchCancelsThePendingRestAlert() async {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let alerts = RecordingAlerts()
        let first = model(store: store, draft: draft, at: now, alerts: alerts)
        first.start()
        await first.add(bench)
        first.setDone(true, set: first.exercises[0].sets[0].id, in: first.exercises[0].id)
        await first.rest.alertsSettled()

        let reopened = model(store: store, draft: draft, at: now, alerts: alerts)
        #expect(!reopened.rest.isActive)
        reopened.discard()
        await reopened.rest.alertsSettled()
        #expect(await alerts.events.last == .cancelled)
        #expect(draft.data == nil)
    }

    @Test func unreadableDraftRequiresExplicitDiscardBeforeStartingAgain() {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let unreadable = Data("unreadable".utf8)
        draft.data = unreadable
        let reopened = model(store: store, draft: draft, at: now)

        #expect(reopened.needsDraftRecovery)
        #expect(!reopened.canResumeWorkout)
        #expect(reopened.draftErrorMessage != nil)
        reopened.start()
        #expect(!reopened.isSessionActive)
        #expect(draft.data == unreadable)

        reopened.discard()
        #expect(draft.data == nil)
        reopened.start()
        #expect(reopened.isSessionActive)
        #expect(draft.data != nil)
    }

    @Test func retryWritesTheCurrentEditsAfterAStorageError() async {
        let store = TestStore(exercises: [bench])
        let draft = DraftStore()
        let first = model(store: store, draft: draft, at: now)
        first.start()
        draft.refusesWrites = true
        first.sessionNotes = "Edited while storage was unavailable"
        #expect(first.draftErrorMessage != nil)

        draft.refusesWrites = false
        first.retryDraftAccess()
        #expect(first.draftErrorMessage == nil)
        let reopened = model(store: store, draft: draft, at: now)
        await reopened.resumeSavedWorkout()
        #expect(reopened.sessionNotes == first.sessionNotes)
    }
}
