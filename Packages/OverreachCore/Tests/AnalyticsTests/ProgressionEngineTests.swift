@testable import Analytics
import Domain
import Foundation
import Testing

/// A deload week that ended on `date`.
private func deloadEnded(_ date: Date, calendar: Calendar = .current) -> LastRecovery {
    LastRecovery(lastDay: CalendarDay(date, calendar: calendar), kind: .deloadWeek)
}

// MARK: - Fixtures

private let baseDate = Date(timeIntervalSince1970: 1_790_000_000)

private func date(day: Int) -> Date {
    baseDate.addingTimeInterval(Double(day) * 86_400)
}

/// One exposure on `day` with the given reps at `weight` (and optional RPE for every set).
private func exposure(day: Int, weight: Double?, reps: [Int], rpe: Double? = nil) -> ExerciseExposure {
    ExerciseExposure(
        date: date(day: day),
        sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: rpe) }
    )
}

private let doubleProgression = ProgressionSettings(scheme: .default, incrementKg: 2.5)
private let linear = ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5)

private func weights(_ target: ExerciseTarget) -> [Double?] { target.sets.map(\.weightKg) }
private func reps(_ target: ExerciseTarget) -> [Int] { target.sets.map(\.reps) }

/// Linear 3×5: three successful sessions up to 100 kg, then three misses at 102.5 kg.
private func stalledSquat(startDay: Int = 0) -> [ExerciseExposure] {
    [
        exposure(day: startDay, weight: 95, reps: [5, 5, 5]),
        exposure(day: startDay + 3, weight: 97.5, reps: [5, 5, 5]),
        exposure(day: startDay + 6, weight: 100, reps: [5, 5, 5]),
        exposure(day: startDay + 9, weight: 102.5, reps: [4, 4, 4]),
        exposure(day: startDay + 12, weight: 102.5, reps: [4, 4, 3]),
        exposure(day: startDay + 15, weight: 102.5, reps: [4, 3, 3]),
    ]
}

// MARK: - Load prescription

@Suite("Load prescription")
struct LoadPrescriptionTests {
    @Test func fiveRepsAtRPE8IsAbout81Percent() throws {
        let fraction = try #require(LoadPrescription.fractionOfOneRepMax(reps: 5, rpe: 8))
        #expect(abs(fraction - 0.8108) < 0.001)
    }

    @Test func estimateAddsRepsInReserveWhenRPEIsReliable() throws {
        let withRPE = try #require(LoadPrescription.estimatedOneRepMax(weightKg: 100, reps: 5, rpe: 8))
        let withoutRPE = try #require(LoadPrescription.estimatedOneRepMax(weightKg: 100, reps: 5, rpe: nil))
        let lowRPE = try #require(LoadPrescription.estimatedOneRepMax(weightKg: 100, reps: 5, rpe: 5))
        #expect(abs(withRPE - 123.333) < 0.001)
        #expect(abs(withoutRPE - 116.667) < 0.001)
        #expect(lowRPE == withoutRPE)
    }

    @Test func highRepSetsAreNotUsedForEstimates() {
        #expect(LoadPrescription.estimatedOneRepMax(weightKg: 50, reps: 15, rpe: 9) == nil)
    }

    @Test func roundsToTheNearestIncrement() {
        #expect(LoadPrescription.round(81.3, toIncrement: 2.5) == 82.5)
        #expect(LoadPrescription.round(81.3, toIncrement: 0) == 81.3)
    }
}

// MARK: - Exposures

@Suite("Exercise exposures")
struct ExerciseExposureTests {
    @Test func historyKeepsStraightWorkingSetsOldestFirst() {
        let squat = UUID()
        let newer = StrengthSession(name: "B", startedAt: date(day: 2), entries: [
            ExerciseEntry(exerciseID: squat, sets: [
                WorkoutSet(kind: .warmup, weightKg: 60, reps: 5),
                WorkoutSet(weightKg: 100, reps: 5),
                WorkoutSet(kind: .dropSet, weightKg: 80, reps: 8),
            ]),
        ])
        let older = StrengthSession(name: "A", startedAt: date(day: 0), entries: [
            ExerciseEntry(exerciseID: squat, sets: [WorkoutSet(weightKg: 97.5, reps: 5)]),
            ExerciseEntry(exerciseID: UUID(), sets: [WorkoutSet(weightKg: 40, reps: 10)]),
        ])

        let history = ExerciseExposure.history(of: squat, in: [newer, older])

        #expect(history.count == 2)
        #expect(history[0].workingWeightKg == 97.5)
        #expect(history[1].sets.count == 1)
        #expect(history[1].workingWeightKg == 100)
    }

    @Test func workingWeightIsTheMostUsedLoad() {
        let mixed = ExerciseExposure(date: baseDate, sets: [
            WorkoutSet(weightKg: 100, reps: 5),
            WorkoutSet(weightKg: 90, reps: 8),
            WorkoutSet(weightKg: 90, reps: 8),
        ])
        #expect(mixed.workingWeightKg == 90)
        #expect(mixed.setsAtWorkingWeight.count == 2)
    }
}

// MARK: - Targets

@Suite("Progression targets")
struct ProgressionTargetsTests {
    @Test func noHistoryGivesRepsWithoutLoad() {
        let target = ProgressionTargets.next(history: [], settings: doubleProgression)
        #expect(target.sets.count == 3)
        #expect(weights(target) == [nil, nil, nil])
        #expect(reps(target) == [8, 8, 8])
        #expect(target.reasons == [.noHistory])
    }

    @Test func doubleProgressionAddsLoadAtTopOfRange() {
        let history = [exposure(day: 0, weight: 60, reps: [12, 12, 12], rpe: 8)]
        let target = ProgressionTargets.next(history: history, settings: doubleProgression)
        #expect(weights(target) == [62.5, 62.5, 62.5])
        #expect(reps(target) == [8, 8, 8])
        #expect(target.reasons == [.topOfRangeReached(reps: 12)])
    }

    @Test func doubleProgressionAddsRepsBeforeLoad() {
        let history = [exposure(day: 0, weight: 60, reps: [12, 11, 10], rpe: 8)]
        let target = ProgressionTargets.next(history: history, settings: doubleProgression)
        #expect(weights(target) == [60, 60, 60])
        #expect(reps(target) == [12, 12, 11])
        #expect(target.reasons == [.addRepsBeforeLoad])
    }

    @Test func doubleProgressionHoldsLoadWhenTopRepsWereTooHard() {
        let history = [exposure(day: 0, weight: 60, reps: [12, 12, 12], rpe: 9.5)]
        let target = ProgressionTargets.next(history: history, settings: doubleProgression)
        #expect(weights(target) == [60, 60, 60])
        #expect(reps(target) == [12, 12, 12])
    }

    @Test func doubleProgressionDropsLoadAfterTwoSessionsBelowRange() {
        let history = [
            exposure(day: 0, weight: 62.5, reps: [8, 7, 6]),
            exposure(day: 3, weight: 62.5, reps: [8, 7, 7]),
        ]
        let target = ProgressionTargets.next(history: history, settings: doubleProgression)
        #expect(weights(target) == [60, 60, 60])
        #expect(target.reasons == [.belowRangeTwice])
    }

    @Test func bodyweightAtTopOfRangeAsksForLoadOrHarderVariation() {
        let settings = ProgressionSettings(scheme: .default, incrementKg: 0)
        let history = [exposure(day: 0, weight: nil, reps: [12, 12, 12])]
        let target = ProgressionTargets.next(history: history, settings: settings)
        #expect(reps(target) == [12, 12, 12])
        #expect(target.reasons.contains(.noLoadIncrementAvailable))
    }

    @Test func linearLoadAddsIncrementAfterSuccess() {
        let target = ProgressionTargets.next(history: [exposure(day: 0, weight: 100, reps: [5, 5, 5])], settings: linear)
        #expect(weights(target) == [102.5, 102.5, 102.5])
        #expect(target.reasons == [.allRepsCompleted])
    }

    @Test func linearLoadRepeatsAfterAMissAndResetsAfterThree() {
        let oneMiss = [exposure(day: 0, weight: 100, reps: [5, 5, 5]), exposure(day: 3, weight: 102.5, reps: [5, 4, 4])]
        let repeated = ProgressionTargets.next(history: oneMiss, settings: linear)
        #expect(weights(repeated) == [102.5, 102.5, 102.5])
        #expect(repeated.reasons == [.repeatAfterMiss(consecutiveMisses: 1)])

        let reset = ProgressionTargets.next(history: stalledSquat(), settings: linear)
        #expect(weights(reset) == [92.5, 92.5, 92.5])  // 102.5 × 0.9 = 92.25 → 92.5
        #expect(reset.reasons == [.resetAfterMisses(consecutiveMisses: 3)])
    }

    @Test func rpeBasedLoadComesFromTheEstimate() throws {
        let settings = ProgressionSettings(scheme: .rpeBased(sets: 3, reps: 3, targetRPE: 9), incrementKg: 2.5)
        let target = ProgressionTargets.next(history: [exposure(day: 0, weight: 100, reps: [5], rpe: 8)], settings: settings)
        // e1RM 123.3 kg; 3 @ RPE 9 ≈ 88.2 % → 108.8 → 110 kg.
        #expect(weights(target) == [110, 110, 110])
        let reason = try #require(target.reasons.last)
        #expect(reason.evidence == ProgressionEvidence.rirBasedRPE)
    }

    @Test func repCycleMovesToTheNextBlock() {
        let settings = ProgressionSettings(scheme: .repCycle(sets: 3, repBlocks: [12, 8, 5], targetRPE: 8), incrementKg: 2.5)
        let target = ProgressionTargets.next(history: [exposure(day: 0, weight: 80, reps: [8, 8, 8], rpe: 8)], settings: settings)
        #expect(reps(target) == [5, 5, 5])
        #expect(target.reasons.first == .nextRepBlock(reps: 5))
    }

    @Test func didMeetComparesLoadAndRepsPerSet() {
        let target = ExerciseTarget(sets: Array(repeating: PlannedSet(weightKg: 100, reps: 5, targetRPE: 8), count: 3), reasons: [])
        #expect(ProgressionTargets.didMeet(target, in: exposure(day: 0, weight: 100, reps: [5, 5, 5])) == true)
        #expect(ProgressionTargets.didMeet(target, in: exposure(day: 0, weight: 100, reps: [5, 5, 4])) == false)
        #expect(ProgressionTargets.didMeet(target, in: exposure(day: 0, weight: 97.5, reps: [5, 5, 5])) == false)
    }
}

// MARK: - Stalls

@Suite("Stall detection")
struct StallDetectionTests {
    @Test func needsMoreThanTheRecentWindow() {
        let history = [exposure(day: 0, weight: 100, reps: [5, 5, 5]), exposure(day: 3, weight: 102.5, reps: [5, 5, 5])]
        #expect(StallDetection.status(history: history, settings: linear) == .notEnoughData)
    }

    @Test func risingEstimateIsProgressing() {
        let history = (0..<5).map { exposure(day: $0 * 3, weight: 100 + Double($0) * 2.5, reps: [5, 5, 5]) }
        #expect(StallDetection.status(history: history, settings: linear) == .progressing)
    }

    @Test func flatEstimateWithMissesIsStalled() throws {
        let status = StallDetection.status(history: stalledSquat(), settings: linear, weeklyFractionalSets: 8)
        guard case let .stalled(suggestions) = status else {
            Issue.record("Expected a stall, got \(status)")
            return
        }
        #expect(suggestions.first == .switchToDoubleProgression)
        #expect(suggestions.contains(.addSet(weeklySets: 8)))
        #expect(!suggestions.contains(.microload(incrementKg: 1.25)))
        #expect(suggestions.last == .deloadLift(loadReduction: 0.1))
    }

    @Test func shortfallIsTheLargestRepGap() {
        let target = ExerciseTarget(sets: Array(repeating: PlannedSet(weightKg: 100, reps: 5, targetRPE: 8), count: 3), reasons: [])
        #expect(StallDetection.shortfall(of: target, in: exposure(day: 0, weight: 100, reps: [5, 5, 4])) == 1)
        #expect(StallDetection.shortfall(of: target, in: exposure(day: 0, weight: 100, reps: [5])) == 5)
    }
}

// MARK: - Deloads

@Suite("Deload advisor")
struct DeloadAdvisorTests {
    private let main = ProgressionSettings(scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5, isMainLift: true)

    @Test func proposesWhenLiftsStallAndADeloadIsDue() throws {
        let lifts = [
            LiftStatus.assess(exerciseID: UUID(), history: stalledSquat(), settings: main, now: date(day: 17)),
            LiftStatus.assess(
                exerciseID: UUID(), history: stalledSquat(startDay: 1), settings: main, now: date(day: 17)
            ),
        ]
        let proposal = try #require(DeloadAdvisor.proposal(
            lifts: lifts, lastRecovery: deloadEnded(date(day: -42)), now: date(day: 17)
        ))
        #expect(proposal.signals.contains(.liftsStalled(count: 2, mainLifts: true)))
        #expect(proposal.signals.contains(.weeksSinceDeload(8)))
        #expect(proposal.plan == .standard)
    }

    @Test func timeAndLoadAloneDoNotTriggerADeload() {
        let progressing = (0..<5).map { exposure(day: $0 * 3, weight: 100 + Double($0) * 2.5, reps: [5, 5, 5]) }
        let lifts = [LiftStatus.assess(exerciseID: UUID(), history: progressing, settings: main, now: date(day: 14))]
        let proposal = DeloadAdvisor.proposal(
            lifts: lifts, lastRecovery: deloadEnded(date(day: -70)),
            weeklyLoad: WeeklyLoadChange(lastWeek: 170, usualWeek: 100),
            now: date(day: 14)
        )
        #expect(proposal == nil)
    }

    @Test func detectsRPECreepAtTheSameLoad() {
        let history = [
            exposure(day: 0, weight: 100, reps: [5, 5, 5], rpe: 7),
            exposure(day: 3, weight: 100, reps: [5, 5, 5], rpe: 7.5),
            exposure(day: 6, weight: 100, reps: [5, 5, 5], rpe: 8.5),
        ]
        #expect(DeloadAdvisor.hasRPECreep(history, since: date(day: -1)))
        #expect(!DeloadAdvisor.hasRPECreep(Array(history.prefix(2)), since: date(day: -1)))
    }

    @Test func detectsAPerformanceDrop() {
        let history = [
            exposure(day: 0, weight: 100, reps: [5, 5, 5]),
            exposure(day: 3, weight: 100, reps: [3, 3, 3]),
        ]
        #expect(DeloadAdvisor.hasPerformanceDrop(history, since: date(day: -1), fraction: 0.03))
    }
}
