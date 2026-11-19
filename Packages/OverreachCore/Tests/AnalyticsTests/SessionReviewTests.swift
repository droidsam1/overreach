@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Session review")
struct SessionReviewTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], secondaryMuscles: [.triceps],
                                 equipment: .barbell)

    private func session(daysAgo: Double, weight: Double, reps: [Int], name: String = "Push") -> StrengthSession {
        StrengthSession(
            name: name, startedAt: now.addingTimeInterval(-daysAgo * 86_400),
            endedAt: now.addingTimeInterval(-daysAgo * 86_400 + 3_000),
            entries: [ExerciseEntry(exerciseID: bench.id, sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: 8) })]
        )
    }

    private func target(_ weight: Double, _ reps: [Int]) -> ExerciseTarget {
        ExerciseTarget(sets: reps.map { PlannedSet(weightKg: weight, reps: $0, targetRPE: 8) }, reasons: [])
    }

    private func review(_ today: StrengthSession, target: ExerciseTarget?, history: [StrengthSession]) -> SessionReview {
        SessionReviewer.review(today, targets: target.map { [bench.id: $0] } ?? [:], history: history,
                               exercises: [bench], settings: [:])
    }

    @Test func outcomesCompareWithTheTarget() {
        let history = [session(daysAgo: 3, weight: 60, reps: [9, 9, 9])]
        let plan = target(60, [10, 10, 10])
        #expect(review(session(daysAgo: 0, weight: 60, reps: [11, 10, 10]), target: plan, history: history)
            .exercises.first?.outcome == .exceeded)
        #expect(review(session(daysAgo: 0, weight: 60, reps: [10, 10, 10]), target: plan, history: history)
            .exercises.first?.outcome == .met)
        #expect(review(session(daysAgo: 0, weight: 60, reps: [10, 9, 8]), target: plan, history: history)
            .exercises.first?.outcome == .below(repsShort: 2))
        var partial = session(daysAgo: 0, weight: 60, reps: [10])
        partial.entries[0].countsForProgression = false
        #expect(review(partial, target: plan, history: history).exercises.first?.outcome == .unfinished)
        #expect(review(session(daysAgo: 0, weight: 60, reps: [10]), target: nil, history: [])
            .exercises.first?.outcome == .noTarget)
    }

    @Test func totalsAdherenceAndComparison() {
        let previous = session(daysAgo: 7, weight: 60, reps: [10, 10, 10])
        let today = session(daysAgo: 0, weight: 62.5, reps: [10, 10, 10])
        let result = review(today, target: target(62.5, [8, 8, 8]), history: [previous])
        #expect(result.workingSets == 3)
        #expect(result.tonnageKg == 1_875)
        #expect(result.previousTonnageKg == 1_800)
        #expect(result.previous?.id == previous.id)
        #expect(result.effectiveSets[.chest] == 3)
        #expect(result.effectiveSets[.triceps] == 1.5)
        #expect(result.exercisesOnTarget == 1)
        #expect(result.exercisesWithTarget == 1)
    }

    @Test func recordsAreBestEstimatesOrRepsAtALoad() {
        let history = [session(daysAgo: 3, weight: 60, reps: [10, 10, 10])]
        let heavier = review(session(daysAgo: 0, weight: 65, reps: [10, 9, 9]), target: nil, history: history)
        guard case .estimatedOneRepMax = heavier.exercises.first?.record else {
            Issue.record("expected an estimated 1RM record")
            return
        }
        let firstTime = review(session(daysAgo: 0, weight: 65, reps: [10]), target: nil, history: [])
        #expect(firstTime.exercises.first?.record == nil)
    }

    @Test func nextTargetCountsThisSession() {
        let history = [session(daysAgo: 3, weight: 60, reps: [11, 11, 11])]
        let today = session(daysAgo: 0, weight: 60, reps: [12, 12, 12])
        let next = review(today, target: target(60, [12, 12, 12]), history: history).exercises.first?.nextTarget
        #expect(next?.sets.first?.weightKg == 62.5)  // top of 8–12 reached
    }
}
