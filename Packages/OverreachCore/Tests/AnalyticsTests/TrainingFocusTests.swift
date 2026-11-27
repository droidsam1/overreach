@testable import Analytics
import Domain
import Foundation
import Testing

// MARK: - Fixtures

private let origin = Date(timeIntervalSince1970: 1_790_000_000)

private func day(_ offset: Int) -> Date { origin.addingTimeInterval(Double(offset) * 86_400) }

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
}

private let squat = Exercise(
    name: "Squat", primaryMuscles: [.quadriceps], secondaryMuscles: [.glutes], equipment: .barbell
)

private func session(
    _ offset: Int, weight: Double, reps: Int, sets: Int = 3, focus: TrainingFocus? = nil
) -> StrengthSession {
    StrengthSession(
        name: "Legs",
        startedAt: day(offset),
        entries: [ExerciseEntry(
            exerciseID: squat.id,
            sets: Array(repeating: WorkoutSet(weightKg: weight, reps: reps), count: sets)
        )],
        focus: focus
    )
}

/// Six squat sessions over three weeks, all 3×10: pure hypertrophy work.
private let hypertrophyOnly = (0..<6).map { session($0 * 3 + 1, weight: 100, reps: 10) }

// MARK: - Classification

@Suite("Focus classification")
struct FocusClassifierTests {
    @Test func classifiesSetsByRepsAndRelativeLoad() {
        #expect(FocusClassifier.focus(of: WorkoutSet(weightKg: 100, reps: 5), oneRepMaxKg: 120) == .strength)
        #expect(FocusClassifier.focus(of: WorkoutSet(weightKg: 80, reps: 5), oneRepMaxKg: 120) == .hypertrophy)
        #expect(FocusClassifier.focus(of: WorkoutSet(weightKg: 80, reps: 10), oneRepMaxKg: 120) == .hypertrophy)
        #expect(FocusClassifier.focus(of: WorkoutSet(weightKg: 40, reps: 20), oneRepMaxKg: 120) == .endurance)
        #expect(FocusClassifier.focus(of: WorkoutSet(kind: .warmup, weightKg: 60, reps: 5), oneRepMaxKg: 120) == nil)
        #expect(FocusClassifier.focus(of: WorkoutSet(weightKg: 100, reps: 3), oneRepMaxKg: nil) == .strength)
    }

    @Test func dominantNeedsAMajorityOtherwiseMixed() {
        #expect(FocusClassifier.dominant([.strength, .strength, .hypertrophy]) == .strength)
        #expect(FocusClassifier.dominant([.strength, .hypertrophy]) == .mixed)
        #expect(FocusClassifier.dominant([]) == nil)
    }

    @Test func sessionFocusUsesThePriorEstimate() {
        let heavy = session(10, weight: 130, reps: 3)
        #expect(FocusClassifier.focus(of: heavy, history: hypertrophyOnly + [heavy]) == .strength)
        #expect(FocusClassifier.focus(of: hypertrophyOnly[0], history: hypertrophyOnly) == .hypertrophy)
    }

    @Test func prescriptionsFollowTheEvidence() {
        let strength = FocusPrescription.for(.strength)
        let hypertrophy = FocusPrescription.for(.hypertrophy)
        #expect(strength.restSeconds.lowerBound >= 180)
        #expect(hypertrophy.restSeconds.lowerBound >= 90)
        #expect(strength.repRange.upperBound <= 6)
        #expect(strength.evidence.contains(FocusEvidence.loadingByGoal))
    }
}

// MARK: - Balance

@Suite("Focus balance")
struct FocusBalanceTests {
    private var threeWeeks: FocusBalance.Settings {
        var settings = FocusBalance.Settings()
        settings.windowDays = 21
        return settings
    }

    @Test func strengthGoalWithOnlyHypertrophyWorkIsFlagged() {
        let profile = AthleteProfile(goal: TrainingGoal(kind: .strength, priorityLifts: [squat.id]))
        let findings = FocusBalance.findings(
            sessions: hypertrophyOnly, exercises: [squat.id: squat], profile: profile, now: day(20), settings: threeWeeks
        )
        #expect(findings.contains(.noHeavyWorkOnPriorityLift(exerciseID: squat.id, days: 21)))
        #expect(findings.contains(.focusStreak(focus: .hypertrophy, sessions: 6)))
        #expect(findings.contains(.muscleSingleFocus(muscle: .quadriceps, focus: .hypertrophy)))
    }

    @Test func aDeclaredBlockMakesTheStreakIntentional() {
        let block = TrainingBlock(focus: .hypertrophy, start: CalendarDay(day(0)), plannedWeeks: 6, isDeclared: true)
        let profile = AthleteProfile(goal: TrainingGoal(kind: .strength), declaredBlocks: [block])
        let findings = FocusBalance.findings(
            sessions: hypertrophyOnly, exercises: [squat.id: squat], profile: profile, now: day(20), settings: threeWeeks
        )
        #expect(!findings.contains { if case .focusStreak = $0 { true } else { false } })
        #expect(!findings.contains { if case .muscleSingleFocus = $0 { true } else { false } })
    }

    @Test func declaredFocusNotMatchedByTheSets() {
        let declaredSession = session(19, weight: 100, reps: 10, focus: .strength)
        let profile = AthleteProfile(goal: TrainingGoal(kind: .general))
        let findings = FocusBalance.findings(
            sessions: hypertrophyOnly + [declaredSession],
            exercises: [squat.id: squat],
            exerciseSettings: [squat.id: ProgressionSettings(incrementKg: 2.5, focus: .strength)],
            profile: profile,
            now: day(20),
            settings: threeWeeks
        )
        #expect(findings.contains(.sessionFocusMismatch(sessionID: declaredSession.id, declared: .strength, observed: .hypertrophy)))
        #expect(findings.contains(.exerciseFocusMismatch(exerciseID: squat.id, declared: .strength, observed: .hypertrophy)))
    }

    @Test func detailedMappingPreservesBroadFocusVolumeWithoutDoubleCounting() {
        let detailed = Exercise(
            id: squat.id, name: "Combined pull", primaryMuscles: [.lats, .upperBack],
            secondaryMuscles: [.upperBack, .rearDelts, .sideDelts]
        )
        let broad = Exercise(
            id: squat.id, name: detailed.name, primaryMuscles: [.back], secondaryMuscles: [.shoulders]
        )
        let profile = AthleteProfile(goal: TrainingGoal(kind: .hypertrophy))
        let expected = FocusBalance.findings(
            sessions: hypertrophyOnly, exercises: [squat.id: broad], profile: profile,
            now: day(20), settings: threeWeeks
        )
        #expect(FocusBalance.findings(
            sessions: hypertrophyOnly, exercises: [squat.id: detailed], profile: profile,
            now: day(20), settings: threeWeeks
        ) == expected)
    }

    @Test func hypertrophyGoalFlagsUntrainedMuscles() {
        let profile = AthleteProfile(goal: TrainingGoal(kind: .hypertrophy))
        let findings = FocusBalance.findings(
            sessions: hypertrophyOnly, exercises: [squat.id: squat], profile: profile, now: day(20), settings: threeWeeks
        )
        #expect(findings.contains(.lowVolume(muscle: .chest, weeklySets: 0)))
        #expect(!findings.contains { if case .lowVolume(.quadriceps, _) = $0 { true } else { false } })
    }
}

// MARK: - Blocks

@Suite("Block advisor")
struct BlockAdvisorTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 16)

    @Test func infersBlocksFromWeeklyFocus() {
        let heavy = (0..<6).map { session(28 + $0 * 3, weight: 130, reps: 3) }
        let blocks = BlockAdvisor.inferBlocks(sessions: hypertrophyOnly + heavy, calendar: utc)
        #expect(blocks.map(\.focus) == [.hypertrophy, .strength])
        #expect(blocks.allSatisfy { !$0.isDeclared })
    }

    @Test func strengthGoalMovesToStrengthAfterAHypertrophyBlock() {
        let current = TrainingBlock(focus: .hypertrophy, start: today.adding(days: -49, calendar: utc), isDeclared: false)
        let advice = BlockAdvisor.suggestion(
            goal: TrainingGoal(kind: .strength), current: current, today: today, calendar: utc
        )
        #expect(advice.next == .strength)
        #expect(advice.switchInWeeks == 0)
        #expect(advice.reasons.contains(.blockLengthReached(weeks: 7)))
        #expect(advice.reasons.contains(.periodizationHelpsStrength))
    }

    @Test func peaksBeforeATargetDate() {
        let goal = TrainingGoal(kind: .strength, targetDate: today.adding(days: 21, calendar: utc))
        let current = TrainingBlock(focus: .hypertrophy, start: today.adding(days: -14, calendar: utc), isDeclared: true)
        let advice = BlockAdvisor.suggestion(goal: goal, current: current, today: today, calendar: utc)
        #expect(advice.next == .strength)
        #expect(advice.reasons.first == .peakForTargetDate(weeksLeft: 3))
    }

    @Test func hypertrophyGoalKeepsGoingUntilTheBlockIsLong() {
        let current = TrainingBlock(focus: .hypertrophy, start: today.adding(days: -28, calendar: utc), isDeclared: true)
        let advice = BlockAdvisor.suggestion(
            goal: TrainingGoal(kind: .hypertrophy), current: current, today: today, calendar: utc
        )
        #expect(advice.next == .hypertrophy)
        #expect(advice.switchInWeeks == 6)
    }

    @Test func yearPlanFillsTheHorizonWithDeloadsBetweenBlocks() {
        let plan = BlockAdvisor.plan(goal: TrainingGoal(kind: .general), current: nil, today: today, calendar: utc)
        #expect(plan.reduce(0) { $0 + $1.weeks } == 52)
        #expect(plan.first?.focus == .hypertrophy)
        #expect(plan.contains { $0.isDeload })
    }

    @Test func strengthPlanEndsWithAPeakAndTaper() {
        let goal = TrainingGoal(kind: .strength, targetDate: today.adding(days: 140, calendar: utc))
        let plan = BlockAdvisor.plan(goal: goal, current: nil, today: today, calendar: utc)
        #expect(plan.reduce(0) { $0 + $1.weeks } == 20)
        #expect(plan.last?.isDeload == true)
        #expect(plan.dropLast().last?.focus == .strength)
    }
}

@Suite("Declaring an exercise focus")
struct DeclaringFocusTests {
    @Test func aSuggestedSchemeFollowsTheFocus() {
        let settings = ProgressionSettings(incrementKg: 2.5).declaring(.strength)
        #expect(settings.focus == .strength)
        #expect(settings.scheme == FocusPrescription.for(.strength).defaultScheme)
        #expect(settings.declaring(.hypertrophy).scheme == FocusPrescription.for(.hypertrophy).defaultScheme)
    }

    @Test func aChosenSchemeStays() {
        let chosen = ProgressionScheme.linearLoad(sets: 5, reps: 5, targetRPE: 8)
        let settings = ProgressionSettings(scheme: chosen, incrementKg: 2.5).declaring(.hypertrophy)
        #expect(settings.scheme == chosen)
        #expect(settings.focus == .hypertrophy)
    }
}
