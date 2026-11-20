import Analytics
import Domain
import Foundation
import Testing

@Suite("Progression from one session")
struct FirstProgressionTests {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let settings = ProgressionSettings(incrementKg: 2.5)

    private func exposure(weight: Double?, rpe: Double?, kind: SetKind = .working) -> ExerciseExposure {
        ExerciseExposure(date: date, sets: (1...4).map { _ in
            WorkoutSet(kind: kind, weightKg: weight, reps: 8, rpe: rpe)
        })
    }

    @Test func previewsEachStrategyFromTheActualSetCountAndWeight() {
        let last = exposure(weight: 100, rpe: 8)
        let choices = FirstProgression.choices(from: last, settings: settings)
        #expect(choices.map(\.strategy) == [.repetitions, .load, .wave])
        #expect(choices.map { $0.target.sets.count } == [4, 4, 4])
        #expect(choices.map { $0.target.sets.first?.reps } == [9, 8, 6])
        #expect(choices.map { $0.target.sets.first?.weightKg } == [100, 102.5, 105])

        let wave = choices.first { $0.strategy == .wave }
        if let wave {
            let heavy = ExerciseExposure(date: date.addingTimeInterval(86_400), sets: (1...4).map { _ in
                WorkoutSet(weightKg: 105, reps: 6, rpe: 8)
            })
            let light = ProgressionTargets.next(history: [last, heavy], settings: wave.settings)
            #expect(light.sets.first?.reps == 10)
            #expect(light.sets.first?.weightKg == 95)
        }
    }

    @Test(arguments: [nil, 9.5] as [Double?])
    func withoutRoomToProgressEachAvailableMethodRepeatsTheLastSets(rpe: Double?) {
        let last = exposure(weight: 100, rpe: rpe)
        let choices = FirstProgression.choices(from: last, settings: settings)
        #expect(choices.map(\.strategy) == [.repetitions, .load])
        for choice in choices {
            #expect(choice.target.sets.map(\.reps) == [8, 8, 8, 8])
            #expect(choice.target.sets.map(\.weightKg) == [100, 100, 100, 100])
            #expect(choice.target.reasons == [rpe == nil ? .repeatWithoutEffort : .repeatAfterHighEffort])
        }
    }

    @Test func failureFlagsAndOversizedEquipmentJumpsAreRespected() {
        let failed = exposure(weight: 100, rpe: 8, kind: .failure)
        let choices = FirstProgression.choices(from: failed, settings: settings)
        #expect(choices.allSatisfy { $0.target.reasons == [.repeatAfterHighEffort] })
        let light = exposure(weight: 10, rpe: 8)
        #expect(FirstProgression.choices(from: light, settings: settings).map(\.strategy) == [.repetitions])
        let bodyweight = exposure(weight: nil, rpe: 8)
        #expect(FirstProgression.choices(from: bodyweight, settings: settings).isEmpty)
        #expect(FirstProgression.choices(from: bodyweight, settings: ProgressionSettings(incrementKg: 0))
            .map(\.strategy) == [.repetitions])
    }

    @Test func mixedLoadsAreRepeatedExactlyWithoutForcingAUniformPreset() {
        let last = ExerciseExposure(date: date, sets: [
            WorkoutSet(weightKg: 100, reps: 5),
            WorkoutSet(weightKg: 85, reps: 8),
            WorkoutSet(kind: .warmup, weightKg: 30, reps: 15),
        ])
        let target = ProgressionTargets.next(history: [last], settings: settings, startFromBaseline: true)
        #expect(target.sets.map(\.weightKg) == [100, 85])
        #expect(target.sets.map(\.reps) == [5, 8])
        #expect(FirstProgression.choices(from: last, settings: settings).isEmpty)
    }
}
