import Domain
import Foundation
import PresentationKit
import Testing
import TodayPresentation

@Suite("Today signals")
struct TodaySignalTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private let format = Format(locale: Locale(identifier: "en_US"))

    private func night(_ offset: Int, hrv: Double? = nil, sleep: Double? = nil, rhr: Double? = nil) -> DailyMetrics {
        var metrics = DailyMetrics(day: today.adding(days: offset, calendar: calendar))
        metrics.hrvRMSSDMs = hrv
        metrics.sleepSeconds = sleep.map { $0 * 3_600 }
        metrics.restingHeartRate = rhr
        return metrics
    }

    private func nights(hrv: Double? = 50, sleep: Double? = 7, rhr: Double? = 52) -> [DailyMetrics] {
        (-6...0).map { night($0, hrv: hrv, sleep: sleep, rhr: rhr) }
    }

    private func inputs(
        _ days: [DailyMetrics], readiness: Readiness, load: TodaySignal.Load? = nil
    ) -> TodaySignal.Inputs {
        .init(
            today: today, metrics: days.last { $0.day == today }, nights: days, readiness: readiness, load: load,
            calendar: calendar, format: format
        )
    }

    private func hrvAudit(_ outcome: ReadinessComparison) -> ReadinessInputAudit {
        .init(input: .hrv(.init(.rmssd, .sleep)), status: .compared, outcome: outcome)
    }

    @Test func greenWithAllDataShowsHRVSleepAndRestingHeartRate() {
        let readiness = Readiness(
            level: .green, inputs: [
                hrvAudit(.within), .init(input: .restingHeartRate, status: .compared, outcome: .within),
                .init(input: .sleep, status: .compared, outcome: .within),
            ]
        )
        let signals = TodaySignal.signals(inputs(nights(), readiness: readiness))
        #expect(signals.map(\.kind) == [.hrv, .sleep, .restingHeartRate])
        #expect(signals.allSatisfy { !$0.isLeading && $0.tone == .green })
        #expect(signals[0].value == "50")
        #expect(signals[0].trend.count == 14)
        #expect(signals[0].trend.last! == 50)
        #expect(signals[0].trend.first! == nil)
    }

    @Test func amberLedByHRVPutsHRVFirstAndLeading() {
        let readiness = Readiness(
            level: .amber, reasons: [.hrvBelowBaseline(nights: 3)], inputs: [hrvAudit(.below)]
        )
        let signals = TodaySignal.signals(inputs(nights(), readiness: readiness))
        #expect(signals.first?.kind == .hrv)
        #expect(signals.first?.isLeading == true)
        #expect(signals.first?.tone == .amber)
        #expect(signals.dropFirst().allSatisfy { !$0.isLeading })
    }

    @Test func leadingReasonMovesItsSignalToTheFront() {
        let readiness = Readiness(level: .amber, reasons: [.restingHeartRateElevated(bpmAboveBaseline: 6)])
        let signals = TodaySignal.signals(inputs(nights(), readiness: readiness))
        #expect(signals.map(\.kind) == [.restingHeartRate, .hrv, .sleep])
    }

    @Test func loadAsReasonReplacesTheLeastInformativeSignal() {
        let load = TodaySignal.Load(value: 1.6, status: "A bit high", tone: .amber, isReason: true)
        let readiness = Readiness(level: .amber)
        let signals = TodaySignal.signals(inputs(nights(), readiness: readiness, load: load))
        #expect(signals.map(\.kind) == [.load, .hrv, .sleep])
        #expect(signals.first?.isLeading == true)
        #expect(signals.first?.value == "1.60")
    }

    @Test func loadThatIsNotAReasonStaysOut() {
        let load = TodaySignal.Load(value: 1.0, status: "In your range", tone: .green, isReason: false)
        let signals = TodaySignal.signals(inputs(nights(), readiness: Readiness(level: .green), load: load))
        #expect(!signals.contains { $0.kind == .load })
    }

    @Test func missingSleepLeavesTwoTiles() {
        let signals = TodaySignal.signals(inputs(nights(sleep: nil), readiness: Readiness(level: .green)))
        #expect(signals.map(\.kind) == [.hrv, .restingHeartRate])
    }

    @Test func noDataShowsNoTiles() {
        let signals = TodaySignal.signals(
            inputs(nights(hrv: nil, sleep: nil, rhr: nil), readiness: Readiness(level: .unknown))
        )
        #expect(signals.isEmpty)
    }

    @Test func sleepStatusComparesWithTheWeek() {
        var days = nights(sleep: 7)
        days[days.count - 1].sleepSeconds = 7.4 * 3_600
        let signals = TodaySignal.signals(inputs(days, readiness: Readiness(level: .green)))
        let sleep = signals.first { $0.kind == .sleep }
        #expect(sleep?.value == "7.4")
        #expect(sleep?.status == "+0.4 h vs week")
    }

    @Test func hrvBandComesFromTheBaselineOnlyWhenPresent() {
        var days = nights()
        days[days.count - 1].hrvBaselineLowMs = 44
        days[days.count - 1].hrvBaselineHighMs = 58
        let withBand = TodaySignal.signals(inputs(days, readiness: Readiness(level: .green)))
        #expect(withBand.first?.band == 44...58)
        let without = TodaySignal.signals(inputs(nights(), readiness: Readiness(level: .green)))
        #expect(without.first?.band == nil)
    }
}
