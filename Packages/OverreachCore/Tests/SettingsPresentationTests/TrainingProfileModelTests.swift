import Domain
import Fixtures
import Foundation
import SettingsPresentation
import Testing

@MainActor
@Suite("Training profile")
struct TrainingProfileModelTests {
    @Test func loadsCurrentAnswersAndSavesEditsWithoutReplacingPlanDetails() async throws {
        let store = TestStore()
        let lift = UUID()
        try await store.save(AthleteProfile(
            sex: .female,
            cycleTracking: .naturalCycle,
            walkingRoutine: WalkingRoutine(hasDog: true, dogName: "Nanuk", usualWalksPerDay: 3),
            goal: TrainingGoal(kind: .strength, priorityLifts: [lift]),
            wearables: [.appleWatch]
        ))
        let model = TrainingProfileModel(profiles: store)
        #expect(!model.canSave)
        await model.load()
        #expect(model.canSave)
        #expect(model.goalKind == .strength)
        #expect(model.cycleTracking == .naturalCycle && model.showsCycleTracking)
        #expect(model.dogName == "Nanuk" && model.walkingRoutine.usualWalksPerDay == 3)
        #expect(model.isSelected(.appleWatch))

        model.goalKind = .hybrid
        model.sex = .male
        model.dogName = "  Nanoq  "
        model.walkingRoutine.walksAreFixed = true
        model.walkingRoutine.canRunDuringWalks = true
        model.setWearable(.appleWatch, isSelected: false)
        model.setWearable(.garmin, isSelected: true)

        #expect(await model.save())
        let updated = try await store.profile()
        #expect(updated.goal?.kind == .hybrid && updated.goal?.priorityLifts == [lift])
        #expect(updated.sex == .male && updated.cycleTracking == .off)
        #expect(updated.walkingRoutine == WalkingRoutine(
            hasDog: true, dogName: "Nanoq", usualWalksPerDay: 3, walksAreFixed: true, canRunDuringWalks: true
        ))
        #expect(updated.wearables == [.garmin])
        #expect(await !store.isOnboardingCompleted())
    }

    @Test func aProfileEditPreservesOtherChangesMadeAfterLoading() async throws {
        let store = TestStore()
        let model = TrainingProfileModel(profiles: store)
        await model.load()
        model.setWearable(.garmin, isSelected: true)

        try await store.save(AthleteProfile(
            walkingRoutine: WalkingRoutine(hasDog: true, dogName: "Nanoq"),
            goal: TrainingGoal(kind: .hybrid),
            effortScale: .repsInReserve
        ))
        #expect(await model.save())
        let updated = try await store.profile()
        #expect(updated.walkingRoutine.hasDog && updated.walkingRoutine.dogName == "Nanoq")
        #expect(updated.goal?.kind == .hybrid && updated.effortScale == .repsInReserve)
        #expect(updated.wearables == [.garmin])
    }

    @Test func failedSaveKeepsTheDogEditForRetryAndTurningOffDogClearsItsName() async throws {
        let store = TestStore()
        try await store.save(AthleteProfile(walkingRoutine: WalkingRoutine(hasDog: true, dogName: "Nanoq")))
        let model = TrainingProfileModel(profiles: store)
        await model.load()
        model.walkingRoutine.hasDog = false
        await store.setFailing(true)

        #expect(await !model.save())
        #expect(model.errorMessage == "Could not save your profile. Try again.")
        #expect(!model.walkingRoutine.hasDog && model.canSave)
        #expect(try await store.profile().walkingRoutine.hasDog)

        await store.setFailing(false)
        #expect(await model.save())
        #expect(model.errorMessage == nil)
        #expect(try await store.profile().walkingRoutine == WalkingRoutine())
    }
}
