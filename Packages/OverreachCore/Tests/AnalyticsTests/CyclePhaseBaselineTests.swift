import Analytics
import Domain
import Foundation
import Testing

/// Phase-aware HRV and resting-HR baselines (`cycle-phase-baselines`, `docs/design/cycle-aware-training.md`).
@Suite("Cycle phase baselines")
struct CyclePhaseBaselineTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 19)

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    /// Synthetic natural cycles of 28 ± 2 days with Garmin's nightly RMSSD around 60 ms and resting HR around 50 bpm
    /// in the follicular phase, and the luteal shift of the evidence: +4 bpm and −10 % RMSSD in the last 14 days.
    private struct Fixture {
        /// Period starts, offsets from today, oldest first. The current cycle lasts 28 days.
        var starts: [Int]
        var metricDays = 165

        init(lengths: [Int] = [27, 29, 28, 26, 30], currentStart: Int = -21, metricDays: Int = 165) {
            var starts = [currentStart]
            for length in lengths.reversed() { starts.insert(starts[0] - length, at: 0) }
            self.starts = starts
            self.metricDays = metricDays
        }

        func isLuteal(_ offset: Int) -> Bool {
            let current = starts.last ?? 0
            let next = (starts + [current + 28]).first { $0 > offset } ?? current + 28
            return next - offset <= 14
        }
    }

    private func events(_ fixture: Fixture) -> [MenstrualEvent] {
        fixture.starts.flatMap { start in
            (0..<5).map { MenstrualEvent(day: day(start + $0), flow: .medium, source: .appleHealth) }
        }
    }

    private func history(
        _ fixture: Fixture, recentRMSSD: [Double]? = nil, todayResting: Double? = nil
    ) -> [DailyMetrics] {
        let wobble: [Double] = [0, 2, -1, 1, -2]
        return (0...fixture.metricDays).map { age in
            let luteal = fixture.isLuteal(-age)
            var metrics = DailyMetrics(day: day(-age), sources: [.garmin])
            metrics.hrvRMSSDMs = (luteal ? 54 : 60) + wobble[age % wobble.count]
            metrics.restingHeartRate = (luteal ? 54 : 50) + wobble[age % wobble.count] / 4
            metrics.sleepSeconds = 7.5 * 3_600
            if let recentRMSSD, age < recentRMSSD.count { metrics.hrvRMSSDMs = recentRMSSD[age] }
            if age == 0, let todayResting { metrics.restingHeartRate = todayResting }
            return metrics
        }
    }

    private func readiness(
        _ history: [DailyMetrics], mode: CycleTrackingMode? = .naturalCycle, events: [MenstrualEvent],
        on offset: Int = 0
    ) -> Readiness {
        ReadinessRules.readiness(
            today: day(offset), history: history.filter { $0.day <= day(offset) }, checkIn: nil,
            cycle: mode.map { CycleContext(mode: $0, events: events) }, calendar: calendar
        )
    }

    // MARK: - Phase baseline

    @Test func aLutealDayAtTheLutealNormIsGreenWithAPhaseBaseline() throws {
        let fixture = Fixture()
        let days = history(fixture)
        let estimate = try #require(CyclePhaseEstimator.estimate(
            on: today, events: events(fixture), mode: .naturalCycle, calendar: calendar
        ))
        #expect(estimate.phase == .luteal)
        #expect(estimate.confidence == .high)

        let phaseAware = readiness(days, events: events(fixture))
        #expect(phaseAware.level == .green)
        #expect(phaseAware.reasons == [.phaseBaseline(window: .luteal, cycles: 2)])
        #expect(phaseAware.hrvCoverage?.metric == .rmssd)
        #expect(phaseAware.hrvCoverage?.canCompare == true)

        // The same week against the whole-cycle baseline looks like poor recovery.
        let overall = readiness(days, mode: nil, events: [])
        #expect(overall.level == .amber)
        #expect(overall.reasons.contains { if case .hrvBelowBaseline = $0 { true } else { false } })
    }

    @Test func aTrulySuppressedLutealDayStillCounts() {
        let fixture = Fixture()
        let low = history(fixture, recentRMSSD: [44, 45, 43, 46, 44, 45, 44])

        let result = readiness(low, events: events(fixture))
        #expect(result.level == .amber)
        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 7)))
        #expect(!result.reasons.contains(.hrvMayReflectCycle))
        #expect(result.reasons.last == .phaseBaseline(window: .luteal, cycles: 2))

        // With resting HR well above the luteal norm too, two physiological signals: red.
        let worse = readiness(
            history(fixture, recentRMSSD: [44, 45, 43, 46, 44, 45, 44], todayResting: 61), events: events(fixture)
        )
        #expect(worse.level == .red)
    }

    @Test func missingHRVLeavesTheRestingHeartRateComparison() {
        let fixture = Fixture()
        let days = history(fixture, todayResting: 61).map { day in
            var day = day
            day.hrvRMSSDMs = nil
            return day
        }

        let result = readiness(days, events: events(fixture))
        #expect(result.hrvCoverage == nil)
        #expect(result.level == .amber)
        #expect(result.reasons.first.map { if case .restingHeartRateElevated = $0 { true } else { false } } == true)
        #expect(result.reasons.last == .phaseBaseline(window: .luteal, cycles: 2))
    }

    // MARK: - Fallbacks

    @Test func oneKnownCycleFallsBackToTheInterimRule() {
        let fixture = Fixture()
        let recent = events(fixture).filter { $0.day >= day(-51) }

        let result = readiness(history(fixture), events: recent)
        #expect(result.level == .amber)
        #expect(result.reasons.contains(.hrvMayReflectCycle))
        #expect(!result.reasons.contains { if case .phaseBaseline = $0 { true } else { false } })
    }

    @Test func irregularCyclesGiveNoPhase() {
        let fixture = Fixture(lengths: [24, 38, 29])

        let estimate = CyclePhaseEstimator.estimate(
            on: today, events: events(fixture), mode: .naturalCycle, calendar: calendar
        )
        #expect(estimate?.confidence == .low)
        #expect(estimate?.reasons == [.irregularCycles])

        let result = readiness(history(fixture), events: events(fixture))
        #expect(!result.reasons.contains { if case .phaseBaseline = $0 { true } else { false } })
    }

    @Test(arguments: [CycleTrackingMode.hormonalContraception, .menopause])
    func hormonalContraceptionKeepsTheOverallBaseline(mode: CycleTrackingMode) {
        let fixture = Fixture()
        let days = history(fixture)

        let result = readiness(days, mode: mode, events: events(fixture))
        #expect(result == readiness(days, mode: nil, events: []))
        #expect(!result.reasons.contains(.hrvMayReflectCycle))
    }

    @Test func aConfidentLutealDayWithoutAPhaseBaselineWidensTheRestingHeartRateThreshold() {
        // Only 40 days of data: previous luteal days of a single cycle.
        let fixture = Fixture(metricDays: 40)

        let shifted = readiness(history(fixture, todayResting: 58.5), events: events(fixture))
        #expect(shifted.reasons.contains(.possibleLutealShift))
        #expect(!shifted.reasons.contains { if case .restingHeartRateElevated = $0 { true } else { false } })
        #expect(!shifted.reasons.contains { if case .phaseBaseline = $0 { true } else { false } })

        let high = readiness(history(fixture, todayResting: 61), events: events(fixture))
        #expect(high.reasons.contains { if case .restingHeartRateElevated = $0 { true } else { false } })
        #expect(!high.reasons.contains(.possibleLutealShift))

        // Without a cycle the same rise counts.
        let overall = readiness(history(fixture, todayResting: 58.5), mode: nil, events: [])
        #expect(overall.reasons.contains { if case .restingHeartRateElevated = $0 { true } else { false } })
    }

    @Test func aConfidentFollicularDayWithoutAPhaseBaselineCountsLowHRV() {
        let fixture = Fixture(currentStart: -9, metricDays: 40)

        let result = readiness(
            history(fixture, recentRMSSD: [44, 45, 43, 46, 44, 45, 44]), events: events(fixture)
        )
        #expect(result.reasons.contains(.hrvBelowBaseline(nights: 7)))
        #expect(!result.reasons.contains(.hrvMayReflectCycle))
        #expect(result.level == .amber)
    }

    // MARK: - Deload signals

    @Test func recoveryTrendInheritsThePhaseBaseline() {
        let fixture = Fixture()
        let days = history(fixture)

        let phaseAware = RecoveryTrend.assess(
            today: today, history: days, checkIns: [],
            cycle: CycleContext(mode: .naturalCycle, events: events(fixture)), calendar: calendar
        )
        let overall = RecoveryTrend.assess(today: today, history: days, checkIns: [], calendar: calendar)

        #expect(phaseAware.hrvTrendLowDays == 0)
        #expect(overall.hrvTrendLowDays > 0)
    }
}
