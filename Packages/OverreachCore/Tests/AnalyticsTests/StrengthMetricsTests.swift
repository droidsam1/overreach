@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Strength metrics")
struct StrengthMetricsTests {
    @Test func epleyEstimateMatchesFormula() throws {
        let estimate = try #require(StrengthMetrics.estimatedOneRepMax(weightKg: 100, reps: 5))
        #expect(abs(estimate - 116.667) < 0.001)
    }

    @Test func singleRepReturnsTheWeight() {
        #expect(StrengthMetrics.estimatedOneRepMax(weightKg: 140, reps: 1) == 140)
    }

    @Test func invalidInputReturnsNil() {
        #expect(StrengthMetrics.estimatedOneRepMax(weightKg: 0, reps: 5) == nil)
        #expect(StrengthMetrics.estimatedOneRepMax(weightKg: 100, reps: 0) == nil)
        #expect(StrengthMetrics.estimatedOneRepMax(weightKg: -10, reps: 3) == nil)
    }

    @Test func tonnageExcludesWarmupsAndIncompleteSets() {
        let sets = [
            WorkoutSet(kind: .warmup, weightKg: 60, reps: 8),
            WorkoutSet(weightKg: 100, reps: 5),
            WorkoutSet(weightKg: 100, reps: 5),
            WorkoutSet(weightKg: 100),  // reps missing: ignored
        ]
        #expect(StrengthMetrics.tonnage(of: sets) == 1000)
    }

    @Test func bestEstimateIgnoresWarmups() throws {
        let sets = [
            WorkoutSet(kind: .warmup, weightKg: 150, reps: 1),
            WorkoutSet(weightKg: 100, reps: 5),
            WorkoutSet(weightKg: 105, reps: 3),
        ]
        let best = try #require(StrengthMetrics.bestEstimatedOneRepMax(in: sets))
        #expect(abs(best - 116.667) < 0.001)  // 100×5 (116.7) beats 105×3 (115.5)
    }

    @Test func effectiveSetsCountPrimaryAndHalfSecondary() {
        let squat = Exercise(
            name: "Back squat",
            primaryMuscles: [.quadriceps, .glutes],
            secondaryMuscles: [.hamstrings]
        )
        let session = StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 0),
            entries: [
                ExerciseEntry(exerciseID: squat.id, sets: [
                    WorkoutSet(kind: .warmup, weightKg: 60, reps: 8),
                    WorkoutSet(weightKg: 100, reps: 5, rpe: 8),
                    WorkoutSet(weightKg: 100, reps: 5, rpe: 8.5),
                    WorkoutSet(weightKg: 100, reps: 5),          // no RPE: counts
                    WorkoutSet(weightKg: 80, reps: 5, rpe: 5),   // too easy: does not count
                ]),
            ]
        )

        let result = StrengthMetrics.effectiveSets(in: session, exercises: [squat.id: squat])

        #expect(result[.quadriceps] == 3)
        #expect(result[.glutes] == 3)
        #expect(result[.hamstrings] == 1.5)
        #expect(result[.chest] == nil)
    }
}
