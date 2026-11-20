@testable import Analytics
import Domain
import Foundation
import Testing

@Suite("Deload proposals with recovery signals")
struct DeloadRecoveryTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let main = ProgressionSettings(
        scheme: .linearLoad(sets: 3, reps: 5, targetRPE: 8), incrementKg: 2.5, isMainLift: true
    )

    private func at(_ day: Int) -> Date { now.addingTimeInterval(Double(day) * 86_400) }

    private func exposure(_ day: Int, _ weight: Double, _ reps: [Int], rpe: Double? = nil) -> ExerciseExposure {
        ExerciseExposure(date: at(day), sets: reps.map { WorkoutSet(weightKg: weight, reps: $0, rpe: rpe) })
    }

    /// Stalled on 102.5 kg for three sessions: a performance signal (2 points with two lifts).
    private var stalled: DeloadAdvisor.Lift {
        DeloadAdvisor.Lift(history: [
            exposure(-18, 95, [5, 5, 5]), exposure(-15, 97.5, [5, 5, 5]), exposure(-12, 100, [5, 5, 5]),
            exposure(-9, 102.5, [4, 4, 4]), exposure(-6, 102.5, [4, 4, 3]), exposure(-3, 102.5, [4, 3, 3]),
        ], settings: main)
    }

    private var progressing: DeloadAdvisor.Lift {
        DeloadAdvisor.Lift(history: (0..<6).map { exposure(-18 + $0 * 3, 100 + Double($0) * 2.5, [5, 5, 5]) },
                           settings: main)
    }

    private let poorRecovery = RecoveryTrend(
        hrvLowDays: 6, restingHeartRateHighDays: 5, shortSleepNights: 5, poorWellbeingCheckIns: 4
    )

    @Test func stallsAloneScoreTwoAndRecoveryTipsItIntoAProposal() throws {
        let lifts = [stalled, stalled]
        #expect(DeloadAdvisor.proposal(lifts: lifts, lastDeload: at(-14), now: now) == nil)

        let proposal = try #require(DeloadAdvisor.proposal(
            lifts: lifts, lastDeload: at(-14), recovery: RecoveryTrend(hrvLowDays: 5), now: now
        ))
        #expect(proposal.signals == [.liftsStalled(count: 2), .hrvSuppressed(days: 5)])
        #expect(proposal.score == 3)
        #expect(proposal.signals.last?.evidence.key == "deload-recovery-signals")
    }

    @Test func recoveryNeverProposesADeloadWithoutAPerformanceSignal() {
        // Overdue and with every recovery signal, but lifting keeps progressing: no deload.
        let proposal = DeloadAdvisor.proposal(
            lifts: [progressing, progressing], lastDeload: at(-70), weeklyLoad: WeeklyLoadChange(lastWeek: 1.7, usualWeek: 1), recovery: poorRecovery,
            now: now
        )
        #expect(proposal == nil)
    }

    @Test func recoveryAddsAtMostTwoPoints() throws {
        let proposal = try #require(DeloadAdvisor.proposal(
            lifts: [stalled, stalled], lastDeload: at(-14), recovery: poorRecovery, now: now
        ))
        #expect(proposal.signals.count == 5)  // all four recovery signals are listed as reasons…
        #expect(proposal.score == 4)  // …but add only 2 points
    }

    @Test func shortRunsOfBadDaysDoNotCount() {
        let mild = RecoveryTrend(hrvLowDays: 4, restingHeartRateHighDays: 3, shortSleepNights: 3, poorWellbeingCheckIns: 2)
        #expect(DeloadAdvisor.proposal(lifts: [stalled, stalled], lastDeload: at(-14), recovery: mild, now: now) == nil)
    }

    @Test func beingSickGivesNoDeload() {
        var sick = poorRecovery
        sick.sickRecently = true
        #expect(DeloadAdvisor.proposal(lifts: [stalled, stalled], lastDeload: at(-60), recovery: sick, now: now) == nil)
    }

    // MARK: Recovery trend

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    /// 60 days of steady data (HRV ~55 ms SDNN, resting HR ~50, 7.5 h sleep), then `recent` adjusts the last week.
    private func history(_ recent: (Int, inout DailyMetrics) -> Void = { _, _ in }) -> [DailyMetrics] {
        let wobble: [Double] = [0, 4, -3, 6, -5, 2, -1, 5, -4, 3]
        return (0...66).map { offset in
            var metrics = DailyMetrics(day: day(-offset), sources: [.appleHealth])
            metrics.hrvSDNNMs = 55 + wobble[offset % wobble.count]
            metrics.restingHeartRate = 50 + wobble[offset % wobble.count] / 5
            metrics.sleepSeconds = 7.5 * 3_600
            if offset < 7 { recent(offset, &metrics) }
            return metrics
        }
    }

    @Test func aSteadyWeekHasNoSignals() {
        let trend = RecoveryTrend.assess(today: today, history: history(), checkIns: [], calendar: calendar)
        #expect(trend == RecoveryTrend())
    }

    @Test func aHardWeekIsCountedDayByDay() {
        let hard = history { offset, metrics in
            metrics.hrvSDNNMs = 42
            metrics.restingHeartRate = 57
            if offset < 5 { metrics.sleepSeconds = 5.5 * 3_600 }
        }
        let checkIns = [
            CheckIn(day: day(0), energy: 2), CheckIn(day: day(-1), soreness: 3), CheckIn(day: day(-2), energy: 1),
            CheckIn(day: day(-9), energy: 1),  // outside the week
        ]

        let trend = RecoveryTrend.assess(today: today, history: hard, checkIns: checkIns, calendar: calendar)

        #expect(trend.hrvLowDays >= 5)
        #expect(trend.restingHeartRateHighDays == 7)
        #expect(trend.shortSleepNights == 5)
        #expect(trend.poorWellbeingCheckIns == 3)
        #expect(!trend.sickRecently)
    }

    @Test func aSickCheckInThisWeekIsNoted() {
        let trend = RecoveryTrend.assess(
            today: today, history: history(), checkIns: [CheckIn(day: day(-3), isSick: true)], calendar: calendar
        )
        #expect(trend.sickRecently)
    }
}

@Suite("Deload week targets")
struct DeloadWeekTargetTests {
    @Test func aDeloadHalvesTheSetsLightensTheLoadAndCapsTheEffort() {
        let target = ExerciseTarget(
            sets: Array(repeating: PlannedSet(weightKg: 102.5, reps: 5, targetRPE: 8), count: 3),
            reasons: [.allRepsCompleted]
        )

        let deload = DeloadPlan.standard.applied(to: target, incrementKg: 2.5)

        #expect(deload.sets == Array(repeating: PlannedSet(weightKg: 92.5, reps: 5, targetRPE: 7), count: 2))
        #expect(deload.reasons.first == .deloadWeek(sets: 2, loadReduction: 0.1, maximumRPE: 7))
        #expect(deload.reasons.last == .allRepsCompleted)
        #expect(deload.reasons.first?.evidence.key == "deload-design")
    }

    @Test func aSingleSetStaysOneAndUnknownLoadsStayUnknown() {
        let target = ExerciseTarget(sets: [PlannedSet(weightKg: nil, reps: 10, targetRPE: 6)], reasons: [.noHistory])

        let deload = DeloadPlan.standard.applied(to: target, incrementKg: 2.5)

        #expect(deload.sets == [PlannedSet(weightKg: nil, reps: 10, targetRPE: 6)])  // RPE already under the cap
    }
}
