@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Warm-up prescription")
struct WarmUpPrescriptionTests {
    private func sets(
        _ weight: Double, reps: Int, rpe: Double = 8, equipment: Equipment = .barbell, increment: Double = 2.5,
        primed: Bool = false
    ) -> [WarmUpSet] {
        WarmUpPrescription.sets(workingWeightKg: weight, reps: reps, targetRPE: rpe, equipment: equipment,
                                incrementKg: increment, primed: primed)
    }

    @Test func intensityFollowsRepsAndRPE() {
        #expect(WarmUpPrescription.intensity(reps: 5, targetRPE: 8) == .heavy)
        #expect(WarmUpPrescription.intensity(reps: 10, targetRPE: 8) == .moderate)
        #expect(WarmUpPrescription.intensity(reps: 15, targetRPE: 8) == .light)
    }

    @Test func heavyWorkGetsALongerRampWithFewerReps() {
        #expect(sets(100, reps: 5) == [
            WarmUpSet(weightKg: 40, reps: 5), WarmUpSet(weightKg: 60, reps: 3),
            WarmUpSet(weightKg: 80, reps: 2), WarmUpSet(weightKg: 90, reps: 1),
        ])
    }

    @Test func moderateWorkGetsTwoSetsEndingNearEightyPercent() {
        #expect(sets(60, reps: 10) == [WarmUpSet(weightKg: 30, reps: 6), WarmUpSet(weightKg: 47.5, reps: 4)])
    }

    @Test func primedMusclesGetOnlyTheLastStep() {
        #expect(sets(100, reps: 5, primed: true) == [WarmUpSet(weightKg: 80, reps: 2)])
        #expect(sets(60, reps: 10, primed: true) == [WarmUpSet(weightKg: 47.5, reps: 4)])
    }

    @Test func barbellSetsStartAtTheEmptyBarWithoutRepeats() {
        #expect(sets(30, reps: 5) == [
            WarmUpSet(weightKg: 20, reps: 5), WarmUpSet(weightKg: 25, reps: 2), WarmUpSet(weightKg: 27.5, reps: 1),
        ])
    }

    @Test func nothingWithoutALoadOrBelowTheBar() {
        #expect(sets(0, reps: 8).isEmpty)
        #expect(sets(80, reps: 8, equipment: .bodyweight).isEmpty)
        #expect(sets(20, reps: 8).isEmpty)
    }

    @Test func repsNeverExceedTheWorkingReps() {
        #expect(sets(60, reps: 3, rpe: 6).allSatisfy { $0.reps <= 3 })
    }

    @Test func warmUpsDoNotCountInTheHistory() {
        let id = UUID()
        let session = StrengthSession(
            name: "A", startedAt: Date(timeIntervalSince1970: 0),
            entries: [ExerciseEntry(exerciseID: id, sets: [
                WorkoutSet(kind: .warmup, weightKg: 40, reps: 5), WorkoutSet(kind: .warmup, weightKg: 60, reps: 3),
                WorkoutSet(weightKg: 80, reps: 5), WorkoutSet(weightKg: 80, reps: 5),
            ])]
        )
        let exposure = ExerciseExposure.history(of: id, in: [session])
        #expect(exposure.first?.sets.count == 2)
        #expect(exposure.first?.workingWeightKg == 80)
        let target = ExerciseTarget(sets: Array(repeating: PlannedSet(weightKg: 80, reps: 5, targetRPE: 8), count: 2),
                                    reasons: [])
        #expect(ProgressionTargets.didMeet(target, in: exposure[0]) == true)
    }
}
