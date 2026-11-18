import Domain
import Fixtures
import Foundation
import OnboardingPresentation
import Testing

@MainActor
@Suite("Onboarding")
struct OnboardingModelTests {
    private func makeModel(
        sessions: [StrengthSession] = []
    ) -> (OnboardingModel, TestStore) {
        let store = TestStore(sessions: sessions)
        return (OnboardingModel(profiles: store, workouts: store, status: store), store)
    }

    @Test func opensOnAnEmptyDeviceUntilHandled() async {
        let (model, store) = makeModel()
        await model.presentIfNeeded()
        #expect(model.isPresented)
        #expect(model.step == .goal)
        #expect(model.progressText == "Step 1 of 4")

        await model.skipSetup()
        #expect(!model.isPresented)
        #expect(await store.isOnboardingCompleted())
        #expect((try? await store.profile()) == AthleteProfile())

        await model.presentIfNeeded()
        #expect(!model.isPresented)
    }

    @Test func existingUsersAreNeverAsked() async {
        let session = StrengthSession(name: "Old", startedAt: Date(timeIntervalSince1970: 0), entries: [])
        let (model, store) = makeModel(sessions: [session])
        await model.presentIfNeeded()
        #expect(!model.isPresented)
        #expect(await store.isOnboardingCompleted())
    }

    @Test func aConfiguredProfileIsNotAskedAgain() async throws {
        let (model, store) = makeModel()
        try await store.save(AthleteProfile(sex: .male))
        await model.presentIfNeeded()
        #expect(!model.isPresented)
    }

    @Test func savesTheAnswers() async throws {
        let (model, store) = makeModel()
        await model.presentIfNeeded()

        model.goalKind = .hybrid
        model.next()
        model.sex = .female
        #expect(model.showsCycleTracking)
        model.cycleTracking = .naturalCycle
        model.next()
        #expect(!model.showsWalkDetails)
        model.hasDog = true
        model.usualWalksPerDay = 3
        model.walksAreFixed = true
        #expect(model.showsWalkDetails)
        model.next()
        #expect(model.step == .start && !model.canSkipStep)

        #expect(await model.finish())
        #expect(!model.isPresented)
        let profile = try await store.profile()
        #expect(profile.goal?.kind == .hybrid)
        #expect(profile.sex == .female && profile.cycleTracking == .naturalCycle)
        #expect(profile.walkingRoutine.hasDog && profile.walkingRoutine.usualWalksPerDay == 3)
        #expect(profile.walkingRoutine.walksAreFixed)
    }

    @Test func cycleTrackingOnlyAppliesWhenItWasAsked() async {
        let (model, _) = makeModel()
        model.sex = .female
        model.cycleTracking = .menopause
        model.sex = .unspecified
        #expect(!model.showsCycleTracking)
        #expect(model.cycleTracking == .off)
    }

    @Test func skippingAStepKeepsWhatWasStored() async throws {
        let (model, store) = makeModel()
        let stored = AthleteProfile(goal: TrainingGoal(kind: .strength, priorityLifts: [UUID()]))
        try await store.save(stored)
        await model.reopen()
        #expect(model.goalKind == .strength)

        model.goalKind = .hypertrophy
        model.skipStep()
        #expect(model.step == .about)
        #expect(await model.finish())
        #expect(try await store.profile() == stored)
    }

    @Test func changingTheGoalKeepsItsOtherFields() async throws {
        let (model, store) = makeModel()
        let lift = UUID()
        try await store.save(AthleteProfile(goal: TrainingGoal(kind: .strength, priorityLifts: [lift])))
        await model.reopen()
        model.goalKind = .general
        #expect(await model.finish())
        #expect(try await store.profile().goal == TrainingGoal(kind: .general, priorityLifts: [lift]))
    }

    @Test func movesBetweenStepsWithinBounds() async {
        let (model, _) = makeModel()
        #expect(!model.canGoBack)
        model.back()
        #expect(model.step == .goal)
        for _ in 0..<6 { model.next() }
        #expect(model.step == .start)
        model.back()
        #expect(model.step == .walking && model.canGoBack)
    }

    @Test func aFailedSaveKeepsTheSetupOpen() async {
        let (model, store) = makeModel()
        await model.presentIfNeeded()
        model.goalKind = .strength
        await store.setFailing(true)

        #expect(await model.finish() == false)
        #expect(model.isPresented)
        #expect(model.errorMessage == "Could not save your answers. Try again or skip the setup.")
        #expect(await !store.isOnboardingCompleted())
    }
}
