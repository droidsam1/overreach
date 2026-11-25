import Analytics
import Domain
import Foundation
import PresentationKit

public enum RunningPulseSensor: String, CaseIterable, Identifiable, Sendable {
    case unknown, watch, strap

    public var id: Self { self }

    public var title: String {
        switch self {
        case .unknown: L10n.text("Unknown or different sensor")
        case .watch: L10n.text("Same watch optical sensor")
        case .strap: L10n.text("Same chest strap")
        }
    }

    var sensorID: String? { self == .unknown ? nil : "confirmed:\(rawValue)" }
}

public struct RunningPulseSensorRow: Identifiable, Sendable {
    public let run: RunActivity
    public let selection: RunningPulseSensor

    public var id: String { run.id }
    public var title: String { run.name ?? L10n.text("Running") }
}

extension PerformanceProgress {
    func runningPulse(
        _ results: [RunningBlockComparison.Result], now: Date, calendar: Calendar, metrics: [DailyMetrics]
    ) -> PerformanceSeries? {
        guard let comparison = RunningBlockComparison.compare(results, window: window) else { return nil }
        let pace = comparison.paceSecondsPerKilometer
        let band = L10n.format(
            "{1}–{2} /km", clock(pace.lowerBound), clock(pace.upperBound)
        )
        let card = makeSeries(
            "garmin-pulse", title: band, unit: .heartRate,
            points: comparison.results.map { observation in
                let effort = observation.effort
                let minutes = clock(effort.durationSeconds)
                let block = L10n.format("Block {1} · {2} measured", String(observation.blockNumber), minutes)
                let day = CalendarDay(observation.run.startedAt, calendar: calendar)
                let sleep = metrics.first { $0.day == day }?.sleepSeconds
                let load = loadDescription(observation.run.trainingLoad)
                let details = [block, sleepDescription(sleep), load].compactMap { $0 }.joined(separator: " · ")
                return PerformancePoint(
                    id: .run(observation.run), date: observation.run.startedAt, value: effort.heartRateBPM,
                    valueText: format.number(effort.heartRateBPM) + " bpm", detail: details
                )
            },
            includesPrevious: true
        )
        var series = card
        series.comparison = L10n.format("Approximate comparison · {1}", series.comparison)
        let observations = comparison.results.map {
            PerformanceTrend.Observation(
                sessionID: $0.run.id, date: $0.run.startedAt, value: $0.effort.heartRateBPM, comparisonKey: band
            )
        }
        switch PerformanceTrend.runningHeartRate(
            observations, through: now, windowDays: window.days, calendar: calendar
        ) {
        case .improving: series.trend = L10n.text("Pulse trending lower at comparable pace")
        case .declining: series.trend = L10n.text("Pulse trending higher at comparable pace")
        case .withinVariability: series.trend = trendText(.withinVariability)
        case .insufficientEvidence, .possiblePlateau: series.trend = trendText(.insufficientEvidence)
        }
        if let cadence = comparison.cadenceStepsPerMinute {
            series.context = L10n.format("Median cadence {1} steps/min", format.number(cadence))
        }
        return series
    }

    private func clock(_ seconds: Double) -> String {
        format.minutesAndSeconds(Int(seconds.rounded()))
    }

    private func loadDescription(_ load: Double?) -> String? {
        guard let load, load.isFinite, load > 0 else { return nil }
        return L10n.format("Garmin load {1}", format.number(load))
    }

    private func sleepDescription(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, (0...86_400).contains(seconds), seconds > 0 else { return nil }
        return L10n.format("Sleep {1} h", format.number(seconds / 3_600, maxFractionDigits: 1))
    }
}
