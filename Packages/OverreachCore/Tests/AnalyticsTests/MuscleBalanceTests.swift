import Analytics
import Domain
import Foundation
import Testing

@Suite("Muscle balance")
struct MuscleBalanceTests {
    private static let day = CalendarDay(year: 2026, month: 11, day: 27)

    @Test(arguments: TrainingGoal.Kind.allCases)
    func distinguishesIndirectWorkAndLowVolumeAcrossGoals(goal: TrainingGoal.Kind) {
        var volume = MuscleBalance.SessionVolume()
        volume.fractionalSets = [.chest: 6, .triceps: 3, .core: 1, .forearms: 1]
        volume.directSets = [.chest: 6]
        let findings = MuscleBalance.findings(input: .init(weekly: volume, sessions: []), goal: goal)
        #expect(findings.contains { $0.rule == .noDirectWork && $0.muscle == .triceps && $0.measuredSets == 0 })
        #expect(findings.contains { $0.rule == .lowVolume && $0.muscle == .triceps && $0.measuredSets == 3 })
        #expect(!findings.contains { $0.muscle == .core || $0.muscle == .forearms })
        #expect(findings.filter { $0.rule == .lowVolume }.allSatisfy { $0.evidence.level == .heuristic })
    }

    @Test func goalThresholdsCanDiffer() {
        var volume = MuscleBalance.SessionVolume()
        volume.fractionalSets = [.triceps: 3]
        volume.directSets = [.triceps: 3]
        var settings = MuscleBalance.Settings()
        settings.minimumWeeklySetsByGoal[.strength] = 3
        let input = MuscleBalance.Input(weekly: volume, sessions: [])
        #expect(!MuscleBalance.findings(input: input, goal: .strength, settings: settings)
            .contains { $0.rule == .lowVolume })
        #expect(MuscleBalance.findings(input: input, goal: .hybrid, settings: settings)
            .contains { $0.rule == .lowVolume })
    }

    @Test func distinguishesWeeklyVolumeAndLargestSession() {
        var weekly = MuscleBalance.SessionVolume()
        weekly.fractionalSets = [.chest: 30, .biceps: 22, .triceps: 21.5]
        weekly.directSets = weekly.fractionalSets
        var session = MuscleBalance.SessionVolume()
        session.fractionalSets = [.biceps: 11.5, .chest: 11]
        let findings = MuscleBalance.findings(input: .init(weekly: weekly, sessions: [session]), goal: .general)
        #expect(findings.contains { $0.rule == .veryHighVolume && $0.muscle == .chest })
        #expect(!findings.contains { $0.rule == .highVolume && $0.muscle == .chest })
        #expect(findings.contains { $0.rule == .highVolume && $0.muscle == .biceps })
        #expect(findings.contains { $0.rule == .highSessionVolume && $0.measuredSets == 11.5 })
        #expect(!findings.contains { $0.rule == .highSessionVolume && $0.muscle == .chest })
    }

    @Test func comparesPushToPullAndChecksDeltAndPullingPatterns() {
        var weekly = MuscleBalance.SessionVolume()
        weekly.fractionalSets = [.chest: 11, .biceps: 20, .upperBack: 8, .rearDelts: 5, .sideDelts: 5]
        weekly.directSets = [.chest: 11, .biceps: 20, .upperBack: 8, .rearDelts: 5]
        weekly.pushSets = 11
        weekly.patternSets = [.horizontalPull: 8, .horizontalPush: 11]
        let findings = MuscleBalance.findings(
            input: .init(weekly: weekly, sessions: [], pullingWindow: weekly), goal: .hypertrophy
        )
        #expect(findings.contains { $0.rule == .lowPullVolume && $0.measuredSets == 8 })
        #expect(findings.filter { $0.rule == .lowDeltVolume }.map(\.muscle) == [.sideDelts])
        #expect(findings.filter { $0.rule == .missingPullPattern }.map(\.pattern) == [.verticalPull])
    }

    @Test func checksQuadWorkWithoutHamstringsAndKeepsKilometresAsContext() {
        var weekly = MuscleBalance.SessionVolume()
        weekly.fractionalSets = [.quadriceps: 10, .glutes: 5]
        weekly.directSets = [.quadriceps: 10]
        let findings = MuscleBalance.findings(
            input: .init(weekly: weekly, sessions: [], hamstringWindow: weekly, runningKilometres: 50), goal: .hybrid
        )
        #expect(findings.contains { $0.rule == .noHamstringWork && $0.runningKilometres == 50 && $0.measuredSets == 0 })
        #expect(findings.contains { $0.rule == .emptyRegion && $0.region == .upper && $0.runningKilometres == nil })
        weekly.patternSets[.hinge] = 3
        let hingeFindings = MuscleBalance.findings(
            input: .init(weekly: weekly, sessions: [], hamstringWindow: weekly), goal: .hybrid
        )
        #expect(!hingeFindings.contains { $0.rule == .noHamstringWork })
    }

    @Test func comparesLaggingMusclesToTheAthletesMedian() {
        var weekly = MuscleBalance.SessionVolume()
        weekly.directSets = [.chest: 12, .biceps: 11, .lats: 10, .triceps: 4.5]
        weekly.fractionalSets = weekly.directSets
        let findings = MuscleBalance.findings(input: .init(weekly: weekly, sessions: []), goal: .general)
        #expect(findings.filter { $0.rule == .laggingMuscle }.map(\.muscle) == [.triceps])
        #expect(findings.contains { $0.rule == .emptyRegion && $0.region == .lower })
    }

    @Test func suppressesIntentionalSpecializationWithKnownEmphasis() {
        var weekly = MuscleBalance.SessionVolume()
        weekly.fractionalSets = [.chest: 24]
        weekly.directSets = weekly.fractionalSets
        weekly.pushSets = 24
        let input = MuscleBalance.Input(weekly: weekly, sessions: [], pullingWindow: weekly)
        let block = TrainingBlock(focus: .hypertrophy, start: Self.day, isDeclared: true, specializedMuscles: [.chest])
        #expect(MuscleBalance.findings(input: input, goal: .hypertrophy, block: block).isEmpty)

        var inferred = block
        inferred.isDeclared = false
        let findings = MuscleBalance.findings(input: input, goal: .hypertrophy, block: inferred)
        #expect(findings.contains { $0.rule == .highVolume })
        #expect(findings.contains { $0.rule == .lowPullVolume })
        #expect(findings.contains { $0.rule == .missingPullPattern })
        #expect(findings.contains { $0.rule == .emptyRegion })
    }

    @Test func historyAndProjectionUseTheSameFractionalAttribution() {
        let row = Exercise(
            name: "Cable row", primaryMuscles: [.upperBack], secondaryMuscles: [.upperBack, .biceps],
            movementPattern: .horizontalPull
        )
        let exercises = [row.id: row]
        let routine = Routine(
            name: "Pull", exerciseIDs: [row.id],
            prescriptions: [.init(exerciseID: row.id, scheme: .linearLoad(sets: 5, reps: 8, targetRPE: 8))]
        )
        let block = TrainingBlock(focus: .strength, start: Self.day, isDeclared: true, routineIDs: [routine.id])
        let projected = MuscleBalance.projection(block: block, routines: [routine], exercises: exercises,
                                                 exerciseSettings: [:])
        let start = Self.day.startDate()
        let sets = [.init(kind: .warmup, reps: 6)] + Array(repeating: WorkoutSet(reps: 8), count: 5)
        let logged = StrengthSession(
            name: "Pull", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [.init(exerciseID: row.id, sets: sets)]
        )
        let recorded = MuscleBalance.history(
            sessions: [logged], exercises: exercises, now: start.addingTimeInterval(7_200)
        )
        #expect(projected?.weekly == recorded?.weekly)
        #expect(recorded?.weekly.fractionalSets == [.upperBack: 5, .biceps: 2.5])
        #expect(recorded?.weekly.directSets == [.upperBack: 5])
        #expect(recorded?.pullingWindow == nil)
        #expect(recorded?.hamstringWindow == nil)
    }

    @Test func projectionWeightsThePartialFinalRotation() {
        let row = Exercise(name: "Row", primaryMuscles: [.upperBack], movementPattern: .horizontalPull)
        let pulldown = Exercise(name: "Pulldown", primaryMuscles: [.lats], movementPattern: .verticalPull)
        let first = Routine(name: "Row day", exerciseIDs: [row.id])
        let second = Routine(name: "Pulldown day", exerciseIDs: [pulldown.id])
        let block = TrainingBlock(
            focus: .strength, start: Self.day, plannedWeeks: 3, isDeclared: true,
            routineIDs: [first.id, second.id], sessionsPerWeek: 1
        )
        let projected = MuscleBalance.projection(
            block: block, routines: [second, first], exercises: [row.id: row, pulldown.id: pulldown],
            exerciseSettings: [:]
        )
        #expect(projected?.weekly.fractionalSets == [.upperBack: 2, .lats: 1])
        #expect(projected?.pullingWindow?.patternSets == [.horizontalPull: 1.5, .verticalPull: 1.5])
        #expect(projected?.hamstringWindow == nil)
    }

    @Test func avoidsFalseShortfallsWhenMappingIsUnknown() {
        let legacy = Exercise(name: "Legacy pulldown", primaryMuscles: [.back])
        let start = Self.day.startDate()
        let logged = StrengthSession(
            name: "Pull", startedAt: start, endedAt: start.addingTimeInterval(3_600),
            entries: [.init(exerciseID: legacy.id, sets: [.init(reps: 8)])]
        )
        let findings = MuscleBalance.findings(
            history: [logged], exercises: [legacy.id: legacy], profile: AthleteProfile(),
            now: start.addingTimeInterval(7_200)
        )
        #expect(!findings.contains { $0.muscle == .lats || $0.muscle == .upperBack })
        #expect(!findings.contains { $0.rule == .emptyRegion && $0.region == .upper })
    }
}
