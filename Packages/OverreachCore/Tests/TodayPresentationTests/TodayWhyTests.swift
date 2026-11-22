import Domain
import Foundation
import PresentationKit
import Testing

@testable import TodayPresentation

@Suite("Today Why")
struct TodayWhyTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    private let today = CalendarDay(year: 2026, month: 11, day: 20)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private let source = URL(string: "https://example.org/evidence")

    private func nights(hrv: Double? = 50, sleep: Double? = 7, rhr: Double? = 52) -> [DailyMetrics] {
        (-6...0).map { offset in
            var metrics = DailyMetrics(day: today.adding(days: offset, calendar: calendar))
            metrics.hrvRMSSDMs = hrv
            metrics.sleepSeconds = sleep.map { $0 * 3_600 }
            metrics.restingHeartRate = rhr
            return metrics
        }
    }

    private func why(
        _ readiness: Readiness, nights days: [DailyMetrics]? = nil, load: TodaySignal.Load? = nil,
        coverageNote: String? = nil, sources: [ReadinessSourceDetail] = []
    ) -> TodayWhy {
        let days = days ?? nights()
        let lines = readiness.reasons.map {
            ReadinessLine(
                text: "\($0)", kind: .supporting, evidence: "Moderate", source: source, readings: []
            )
        }
        return TodayWhy.make(
            .init(
                signals: .init(
                    today: today, metrics: days.last { $0.day == today }, nights: days, readiness: readiness,
                    load: load, calendar: calendar, format: format
                ),
                lines: lines, trainingContext: nil, sources: sources, coverageNote: coverageNote
            )
        )
    }

    @Test func amberWithHRVAndLoadWeighsInOrderAndShowsCards() {
        let readiness = Readiness(
            level: .amber, reasons: [.hrvBelowBaseline(nights: 3), .restingHeartRateElevated(bpmAboveBaseline: 6)],
            inputs: [.init(input: .hrv(.init(.rmssd, .sleep)), status: .compared, outcome: .below)]
        )
        let load = TodaySignal.Load(value: 1.6, status: "A bit high", tone: .amber, isReason: true)
        let result = why(readiness, load: load)

        #expect(result.safetyText == nil)
        #expect(result.weights.map(\.weight) == [2, 1])
        #expect(result.weights.allSatisfy { $0.tone == .amber })
        #expect(result.cards.map(\.signal.kind) == [.hrv, .restingHeartRate, .load])
        #expect(result.cards.first?.signal.trend.count == 14)
        #expect(result.cards.first?.evidence == "Moderate")
        #expect(result.cards.first?.source == source)
        #expect(result.cards.last?.isGauge == true)
        // Sleep is in range and no reason: a normal signal, not a card.
        #expect(result.normal.map(\.kind) == [.sleep])
        #expect(result.normalWeight == 1)
    }

    @Test func redWithSicknessHasSafetyTextFirstAndNoSignalCards() {
        let result = why(Readiness(level: .red, reasons: [.markedSick]))
        #expect(result.safetyText != nil)
        #expect(result.cards.isEmpty)
        #expect(result.normal.isEmpty)
        #expect(result.weights.map(\.tone) == [.red])
    }

    @Test func greenShowsOnlyNormalSignals() {
        let readiness = Readiness(
            level: .green, inputs: [.init(input: .hrv(.init(.rmssd, .sleep)), status: .compared, outcome: .within)]
        )
        let result = why(readiness)
        #expect(result.weights.isEmpty)
        #expect(result.cards.isEmpty)
        #expect(result.normal.map(\.kind) == [.hrv, .sleep, .restingHeartRate])
        #expect(result.normal.first?.value == "50")
    }

    @Test func missingDataExplainsCoverageInARow() {
        let readiness = Readiness(level: .unknown, reasons: [.missingData])
        let result = why(
            readiness, nights: nights(hrv: nil, sleep: nil, rhr: nil),
            coverageNote: "Still building your usual HRV range."
        )
        #expect(result.weights.isEmpty)
        #expect(result.cards.isEmpty)
        #expect(result.normal.isEmpty)
        let row = result.rows.first { $0.kind == .sourcesAndCoverage }
        #expect(row?.detail == "Still building your usual HRV range.")
    }
}
