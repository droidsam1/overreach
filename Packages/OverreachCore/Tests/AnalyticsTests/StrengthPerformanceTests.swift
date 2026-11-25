import Analytics
import Domain
import Foundation
import Testing

struct StrengthPerformanceTests {
    private let benchID = UUID.stable("builtin-exercise|Bench Press (Barbell)")
    private let squatID = UUID.stable("builtin-exercise|Squat (Barbell)")
    private let sampleDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func recordedSetsRetainSourceFromFinalizedAndLegacySessions() throws {
        let warmup = WorkoutSet(kind: .warmup, weightKg: 120, reps: 5)
        let heavy = WorkoutSet(weightKg: 100, reps: 3)
        let repBest = WorkoutSet(weightKg: 90, reps: 5)
        let legacySet = WorkoutSet(weightKg: 80, reps: 6)
        let local = workout([warmup, heavy, repBest], at: 60)
        let source = workout([legacySet], source: .strongImport, at: 0, completed: false)
        let draft = workout([WorkoutSet(weightKg: 200, reps: 5)], at: 120, completed: false)
        let future = workout([WorkoutSet(weightKg: 200, reps: 5)], at: 300)
        let invalid = workout([WorkoutSet(weightKg: .infinity, reps: 5), WorkoutSet(weightKg: 90, reps: 0)], at: 180)
        let sets = recordedSets(in: [local, source, draft, future, invalid])

        #expect(Set(sets.map(\.setID)) == Set([heavy.id, repBest.id, legacySet.id]))
        let localSets = sets.filter { $0.source == .app }
        let imported = sets.filter { $0.source == .strongImport }
        let record = try #require(StrengthPerformance.record(in: localSets, matching: .heaviestLoad))
        #expect(record.sessionID == local.id)
        #expect(record.setID == heavy.id)
        #expect(StrengthPerformance.record(in: localSets, matching: .loadAtReps(5))?.setID == repBest.id)
        #expect(StrengthPerformance.record(in: imported, matching: .loadAtReps(6))?.setID == legacySet.id)
        #expect(StrengthPerformance.record(in: sets, matching: .heaviestLoad) == nil)
    }

    @Test func recordedSetsMatchNormalizedWeightAndKeepEarliestTie() {
        let localKg = WorkoutSet(weightKg: 100, reps: 7)
        let pounds = WorkoutSet(weightKg: WeightUnit.pounds.kilograms(from: 220.462), reps: 7)
        let earlier = workout([localKg], at: 0)
        let later = workout([pounds], at: 60)
        let sets = recordedSets(in: [later, earlier])
        let observations = StrengthPerformance.records(in: sets, matching: .repsAtLoad(100))

        #expect(observations.map(\.sessionID) == [earlier.id, later.id])
        #expect(StrengthPerformance.record(in: sets, matching: .repsAtLoad(100))?.setID == localKg.id)
        #expect(StrengthPerformance.record(in: sets, matching: .heaviestLoad)?.setID == localKg.id)
    }

    @Test func strengthRecordsKeepUnilateralAndMachineVariantsSeparate() {
        let oneArm = UUID.stable("builtin-exercise|Bent Over One Arm Row (Dumbbell)")
        let machine = UUID.stable("builtin-exercise|Seated Row (Machine)")
        let bilateral = UUID.stable("builtin-exercise|Bent Over Row (Barbell)")
        let unilateralSet = WorkoutSet(weightKg: 30, reps: 6)
        let sets = recordedSets(in: [
            workout([unilateralSet], exerciseID: oneArm, at: 0),
            workout([WorkoutSet(weightKg: 60, reps: 6)], exerciseID: machine, at: 60),
            workout([WorkoutSet(weightKg: 60, reps: 6)], exerciseID: bilateral, at: 120)
        ])
        let unilateral = sets.filter { $0.exerciseID == oneArm }

        #expect(StrengthPerformance.records(in: sets, matching: .heaviestLoad).isEmpty)
        #expect(StrengthPerformance.record(in: unilateral, matching: .heaviestLoad)?.weightKg == 30)
        #expect(StrengthPerformance.record(in: unilateral, matching: .heaviestLoad)?.setID == unilateralSet.id)
    }

    @Test func recordedMaxSingleRequiresRecordedMaxEffort() {
        let single = WorkoutSet(weightKg: 100, reps: 1, rpe: 10)
        let history = recordedSets(in: [
            workout([single, WorkoutSet(kind: .dropSet, weightKg: 130, reps: 1, rpe: 10)], at: 0),
            workout([WorkoutSet(weightKg: 110, reps: 1)], at: 60),
            workout([WorkoutSet(weightKg: 120, reps: 1, rpe: 9)], at: 120),
            workout([WorkoutSet(weightKg: 140, reps: 1, rpe: 10)], source: .strongImport, at: 180)
        ])
        let local = history.filter { $0.source == .app }
        let imported = history.filter { $0.source == .strongImport }

        #expect(StrengthPerformance.records(in: local, matching: .measuredOneRepMax).map(\.setID) == [single.id])
        #expect(StrengthPerformance.records(in: imported, matching: .measuredOneRepMax).isEmpty)
    }

    @Test func strengthEstimateUsesEligibleLocalSetsAndVersionsByCatalogExercise() throws {
        let eligible = WorkoutSet(weightKg: 100, reps: 6, rpe: 8)
        let lighter = WorkoutSet(weightKg: 85, reps: 5, rpe: 10)
        let invalidSets = [
            WorkoutSet(weightKg: 150, reps: 5),
            WorkoutSet(weightKg: 150, reps: 5, rpe: 7.5),
            WorkoutSet(weightKg: 150, reps: 5, rpe: 11),
            WorkoutSet(weightKg: 150, reps: 1, rpe: 10),
            WorkoutSet(weightKg: 150, reps: 7, rpe: 10),
            WorkoutSet(kind: .dropSet, weightKg: 150, reps: 5, rpe: 10),
            WorkoutSet(kind: .warmup, weightKg: 150, reps: 5, rpe: 10)
        ]
        let sessions = [
            workout([lighter, eligible], at: 0),
            workout(invalidSets, at: 60),
            workout([WorkoutSet(weightKg: 110, reps: 5, rpe: 9)], source: .strongImport, at: 120),
            workout([WorkoutSet(weightKg: 150, reps: 2, rpe: 10)], exerciseID: squatID, at: 180)
        ]
        let sets = recordedSets(in: sessions)
        let bench = try #require(ExerciseCatalog.builtIn.first { $0.id == benchID })
        let squat = try #require(ExerciseCatalog.builtIn.first { $0.id == squatID })
        let incline = try #require(ExerciseCatalog.builtIn.first { $0.name == "Incline Bench Press (Barbell)" })
        let benchEstimates = StrengthPerformance.estimatedOneRepMax(in: sets, exercise: bench)
        let estimate = try #require(benchEstimates.first)
        let squatEstimate = try #require(StrengthPerformance.estimatedOneRepMax(in: sets, exercise: squat).first)

        #expect(benchEstimates.count == 1)
        #expect(estimate.set.sessionID == sessions[0].id)
        #expect(estimate.set.setID == eligible.id)
        #expect(estimate.repsInReserve == 2)
        #expect(abs(estimate.weightKg - 126.6667) < 0.001)
        #expect(estimate.equationVersion == 1)
        #expect(squatEstimate.equationVersion == 1)
        #expect(squatEstimate.weightKg == 160)
        #expect(StrengthPerformance.equationVersion(for: incline) == nil)
        #expect(StrengthPerformance.estimatedOneRepMax(in: sets, exercise: incline).isEmpty)
    }

    private func recordedSets(in sessions: [StrengthSession]) -> [StrengthPerformance.RecordedSet] {
        StrengthPerformance.recordedSets(in: sessions, through: sampleDate.addingTimeInterval(240))
    }

    private func workout(
        _ sets: [WorkoutSet], exerciseID: UUID? = nil, source: DataSourceKind = .app, at offset: TimeInterval,
        completed: Bool = true
    ) -> StrengthSession {
        let startedAt = sampleDate.addingTimeInterval(offset)
        return StrengthSession(
            name: "Strength session", startedAt: startedAt, endedAt: completed ? startedAt.addingTimeInterval(30) : nil,
            entries: [ExerciseEntry(exerciseID: exerciseID ?? benchID, sets: sets)], source: source
        )
    }
}
