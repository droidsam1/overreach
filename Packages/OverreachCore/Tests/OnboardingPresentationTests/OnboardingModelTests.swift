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
        #expect(model.progressText == "Step 1 of 2")

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

    @Test func theFirstRunAsksOnlyTheGoalAndTheDevices() async throws {
        let (model, store) = makeModel()
        await model.presentIfNeeded()
        #expect(model.steps == [.goal, .devices])
        #expect(model.canSkipStep && !model.isLastStep)

        model.goalKind = .hybrid
        model.next()
        #expect(model.step == .devices)
        #expect(model.progressText == "Step 2 of 2")
        #expect(model.isLastStep && !model.canSkipStep)
        #expect(model.usesOnlyPhone && !model.offersGarminSetup)
        model.toggle(.garmin)
        model.toggle(.appleWatch)
        #expect(model.offersGarminSetup && model.isSelected(.appleWatch))
        model.next()
        #expect(model.step == .devices)

        #expect(await model.finish())
        #expect(!model.isPresented)
        let profile = try await store.profile()
        #expect(profile.goal?.kind == .hybrid)
        #expect(profile.wearables == [.garmin, .appleWatch])
        // Nothing else was asked: those questions wait for Today.
        #expect(profile.sex == nil && profile.cycleTracking == .off)
        #expect(profile.walkingRoutine == WalkingRoutine())
    }

    @Test func theTrainingProfileKeepsEveryQuestionEditable() async throws {
        let (model, store) = makeModel()
        await model.reopen()
        #expect(model.steps == [.goal, .about, .walking, .devices])
        #expect(model.progressText == "Step 1 of 4")

        model.goalKind = .hybrid
        model.next()
        model.sex = .female
        #expect(model.showsCycleTracking)
        model.cycleTracking = .naturalCycle
        model.next()
        #expect(!model.showsWalkDetails)
        model.hasDog = true
        model.dogName = "  Nanoq "
        model.usualWalksPerDay = 3
        model.walksAreFixed = true
        #expect(model.showsWalkDetails)
        model.next()
        #expect(model.step == .devices && model.isLastStep)

        #expect(await model.finish())
        let profile = try await store.profile()
        #expect(profile.sex == .female && profile.cycleTracking == .naturalCycle)
        #expect(profile.walkingRoutine.hasDog && profile.walkingRoutine.usualWalksPerDay == 3)
        #expect(profile.walkingRoutine.walksAreFixed)
        #expect(profile.walkingRoutine.dogName == "Nanoq")
    }

    @Test func onlyThePhoneClearsTheWatches() async throws {
        let (model, store) = makeModel()
        try await store.save(AthleteProfile(wearables: [.garmin]))
        await model.reopen()
        #expect(model.isSelected(.garmin))

        model.chooseOnlyPhone()
        #expect(model.usesOnlyPhone && !model.offersGarminSetup)
        model.toggle(.otherWatch)
        model.toggle(.otherWatch)
        #expect(model.usesOnlyPhone)
        #expect(await model.finish())
        #expect(try await store.profile().wearables.isEmpty)
    }

    @Test func finishingTheLastStepKeepsTheStoredWatches() async throws {
        let (model, store) = makeModel()
        try await store.save(AthleteProfile(wearables: [.appleWatch]))
        await model.reopen()
        model.next()
        model.next()
        model.next()
        #expect(model.step == .devices)
        #expect(await model.finish())
        #expect(try await store.profile().wearables == [.appleWatch])
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
        #expect(model.step == .devices)
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
