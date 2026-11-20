import Analytics
import Domain
import Foundation
import Testing

@Suite("Cycle phase estimator")
struct CyclePhaseEstimatorTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let today = CalendarDay(year: 2026, month: 11, day: 19)

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset, calendar: calendar) }

    /// Periods of `flowDays` days starting at each offset from today, as Apple Health logs them.
    private func periods(_ starts: [Int], flowDays: Int = 5) -> [MenstrualEvent] {
        starts.flatMap { start in
            (0..<flowDays).map { MenstrualEvent(day: day(start + $0), flow: .medium, source: .appleHealth) }
        }
    }

    /// Period starts (offsets from today) for cycles of the given lengths, the last one starting `lastStart`.
    private func starts(lengths: [Int], lastStart: Int) -> [Int] {
        var result = [lastStart]
        for length in lengths.reversed() { result.insert(result[0] - length, at: 0) }
        return result
    }

    private func estimate(_ events: [MenstrualEvent], on offset: Int = 0, mode: CycleTrackingMode = .naturalCycle)
        -> CyclePhaseEstimate? {
        CyclePhaseEstimator.estimate(on: day(offset), events: events, mode: mode, calendar: calendar)
    }

    // MARK: - Modes and missing data

    @Test(arguments: [CycleTrackingMode.off, .hormonalContraception, .menopause])
    func onlyANaturalCycleGetsAPhase(mode: CycleTrackingMode) {
        let events = periods(starts(lengths: [28, 28, 28], lastStart: -10))
        #expect(estimate(events, mode: mode) == nil)
    }

    @Test func noPeriodYetGivesNoEstimate() {
        #expect(estimate([]) == nil)
        // A period logged after the day being estimated is not known on that day.
        #expect(estimate(periods([2])) == nil)
    }

    // MARK: - Windows

    @Test func regularCyclesGiveHighConfidenceWindows() throws {
        // Cycles of 27, 29, 28 and 28 days: median 28, so N = S + 28.
        let events = periods(starts(lengths: [27, 29, 28, 28], lastStart: 0))

        let first = try #require(estimate(events))
        #expect(first.cycleDay == 1)
        #expect(first.expectedLength == 28)
        #expect(first.confidence == .high)
        #expect(first.reasons.isEmpty)

        let phases = (0..<28).map { estimate(events, on: $0)?.phase }
        #expect(phases[0...4].allSatisfy { $0 == .menstrual })
        #expect(phases[5...13].allSatisfy { $0 == .follicular })   // until N − 15
        #expect(phases[14...22].allSatisfy { $0 == .luteal })      // N − 14 … N − 6
        #expect(phases[23...27].allSatisfy { $0 == .lateLuteal })  // N − 5 … N − 1
    }

    @Test func neverEstimatesOvulation() {
        let events = periods(starts(lengths: [26, 30, 28, 27, 29, 28], lastStart: -40))
        for offset in -40...0 {
            #expect(estimate(events, on: offset)?.phase != .ovulatory)
        }
    }

    @Test func theMenstrualWindowIsTheLoggedFlowDaysUpToDaySeven() {
        // Only the first two days logged: day 4 is follicular.
        let short = periods(starts(lengths: [28, 28], lastStart: -3), flowDays: 2)
        #expect(estimate(short)?.phase == .follicular)

        // A day without logged flow inside the first week is follicular too.
        var gap = periods(starts(lengths: [28, 28], lastStart: -4), flowDays: 5)
        gap.removeAll { $0.day == day(-1) }
        #expect(estimate(gap, on: -1)?.phase == .follicular)
        #expect(estimate(gap, on: 0)?.phase == .menstrual)

        // Flow logged for 9 days: from day 8 it is follicular.
        let long = periods(starts(lengths: [28, 28], lastStart: -7), flowDays: 9)
        #expect(estimate(long)?.phase == .follicular)
    }

    @Test func expectedLengthIsTheMedianOfTheLastSixCycles() {
        // Seven complete cycles; the oldest (35) is left out. Last six: 26, 27, 28, 29, 30, 30 → 28.5 → 29.
        let events = periods(starts(lengths: [35, 26, 27, 28, 29, 30, 30], lastStart: -3))
        #expect(estimate(events)?.expectedLength == 29)
    }

    // MARK: - Cycle starts

    @Test func flowAfterTenDryDaysStartsACycleButSpottingDoesNot() {
        // A period, a bleed 8 days after it ended, then a period 28 days after the first.
        let period = periods([-40])
        let spotting = [MenstrualEvent(day: day(-27), flow: .light, source: .appleHealth)]
        let next = periods([-12])
        let starts = CyclePhaseEstimator.cycleStarts(events: period + spotting + next, calendar: calendar)
        #expect(starts == [day(-40), day(-12)])
    }

    @Test func anExplicitStartFromHealthCounts() {
        // Health marks a new cycle only 9 dry days after the last flow.
        var events = periods([-30])
        events.append(MenstrualEvent(day: day(-16), flow: .medium, isCycleStart: true, source: .appleHealth))
        let starts = CyclePhaseEstimator.cycleStarts(events: events, calendar: calendar)
        #expect(starts == [day(-30), day(-16)])
    }

    // MARK: - Confidence

    @Test func fewCyclesUseTwentyEightDaysWithLowConfidence() throws {
        let result = try #require(estimate(periods(starts(lengths: [31], lastStart: -18))))
        #expect(result.expectedLength == 28)
        #expect(result.confidence == .low)
        #expect(result.reasons == [.fewCycles])
        #expect(result.usableWindow == nil)
        #expect(result.baselineWindow == .luteal)
    }

    @Test func irregularCyclesHaveLowConfidence() throws {
        let result = try #require(estimate(periods(starts(lengths: [24, 38, 29], lastStart: -18))))
        #expect(result.confidence == .low)
        #expect(result.reasons == [.irregularCycles])
    }

    @Test func aSpreadOverSevenDaysIsIrregularEvenInsideTheNormalRange() throws {
        let result = try #require(estimate(periods(starts(lengths: [22, 30, 26], lastStart: -10))))
        #expect(result.reasons == [.irregularCycles])
    }

    @Test func overdueAfterThreeDaysLate() throws {
        let events = periods(starts(lengths: [28, 28, 28], lastStart: -30))

        // N + 1 (cycle day 30): still late luteal with high confidence.
        let late = try #require(estimate(events, on: -1))
        #expect(late.phase == .lateLuteal)
        #expect(late.confidence == .high)

        // N + 3 is the last day; N + 4 is overdue: no phase is assumed.
        #expect(estimate(events, on: 1)?.confidence == .high)
        let overdue = try #require(estimate(events, on: 2))
        #expect(overdue.phase == .unknown)
        #expect(overdue.confidence == .low)
        #expect(overdue.reasons == [.overdue])
        #expect(overdue.baselineWindow == nil)
    }

    @Test func aPastDayUsesOnlyTheEventsKnownThen() throws {
        // On day −10 the period that started on day −5 was not known yet: cycle day 24 of the previous cycle.
        let events = periods(starts(lengths: [28, 28, 28], lastStart: -5))
        let past = try #require(estimate(events, on: -10))
        #expect(past.cycleDay == 24)
        #expect(past.phase == .lateLuteal)
        #expect(past.confidence == .high)
        // With only one complete cycle before it, the same day had low confidence.
        let earlier = periods(starts(lengths: [28, 28, 28], lastStart: -5)).filter { $0.day >= day(-61) }
        #expect(try #require(estimate(earlier, on: -10)).reasons == [.fewCycles])
    }
}
