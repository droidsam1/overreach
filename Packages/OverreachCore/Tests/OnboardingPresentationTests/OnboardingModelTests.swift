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

    @Test func theFirstRunSavesGoalDevicesAndWeightUnit() async throws {
        let (model, store) = makeModel()
        await model.presentIfNeeded()
        #expect(model.canSkipStep && !model.isLastStep)

        model.goalKind = .hybrid
        model.next()
        #expect(model.step == .devices)
        #expect(model.progressText == "Step 2 of 2")
        #expect(model.isLastStep && !model.canSkipStep)
        #expect(model.usesOnlyPhone && !model.offersGarminSetup)
        model.toggle(.garmin)
        model.toggle(.appleWatch)
        model.weightUnit = .pounds
        #expect(model.offersGarminSetup && model.isSelected(.appleWatch))
        model.next()
        #expect(model.step == .devices)

        #expect(await model.finish())
        #expect(!model.isPresented)
        let profile = try await store.profile()
        #expect(profile.goal?.kind == .hybrid)
        #expect(profile.wearables == [.garmin, .appleWatch])
        #expect(profile.weightUnit == .pounds)
        // Nothing else was asked: those questions wait for Today.
        #expect(profile.sex == nil && profile.cycleTracking == .off)
        #expect(profile.walkingRoutine == WalkingRoutine())
    }

    @Test func onlyThePhoneClearsTheWatches() async throws {
        let (model, store) = makeModel()
        await model.presentIfNeeded()
        model.next()
        model.toggle(.garmin)
        #expect(model.isSelected(.garmin))

        model.chooseOnlyPhone()
        #expect(model.usesOnlyPhone && !model.offersGarminSetup)
        model.toggle(.otherWatch)
        model.toggle(.otherWatch)
        #expect(model.usesOnlyPhone)
        #expect(await model.finish())
        #expect(try await store.profile().wearables.isEmpty)
    }

    @Test func skippingTheGoalLeavesItUnset() async throws {
        let (model, store) = makeModel()
        await model.presentIfNeeded()

        model.goalKind = .hypertrophy
        model.skipStep()
        #expect(model.step == .devices)
        #expect(await model.finish())
        #expect(try await store.profile().goal == nil)
    }

    @Test func movesBetweenStepsWithinBounds() async {
        let (model, _) = makeModel()
        #expect(!model.canGoBack)
        model.back()
        #expect(model.step == .goal)
        for _ in 0..<6 { model.next() }
        #expect(model.step == .devices)
        model.back()
        #expect(model.step == .goal && !model.canGoBack)
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
