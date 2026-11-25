import Analytics
import Domain
import Foundation
import PresentationKit
import TrainingServices

/// The interval of the trend charts in Recovery & Progress.
public enum TrendRange: Int, CaseIterable, Identifiable, Sendable {
    case days30 = 30, days90 = 90

    public var id: Int { rawValue }
    public var days: Int { rawValue }
    public var title: String { L10n.format("{1} days", String(rawValue)) }
}

/// One value of a chart: a day (lines) or the week that starts on `day` (bars).
public struct TrendPoint: Hashable, Sendable {
    public let day: Date
    public let value: Double
    /// Short date for the axis and the spoken summary.
    public let label: String
}

/// A chart with its text summary. The summary names the metric, interval, units and key values, so VoiceOver gets
/// the takeaway without reading the plot.
public struct TrendChart: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case hrv, restingHeartRate, sleep, strengthVolume, runningDistance
    }

    public enum Style: Hashable, Sendable {
        case line, bars
    }

    public let kind: Kind
    public let style: Style
    public let title: String
    public let unit: String
    /// "Last 30 days".
    public let interval: String
    /// Lines keep one slot per day, including gaps. Bars use one slot per week.
    let points: [TrendPoint?]
    public let startLabel: String?
    public let endLabel: String?
    /// The full date interval, including days before the first or after the last available reading.
    public let dateDomain: ClosedRange<Date>?
    public let partialWeekLabel: String?
    /// A personal reference band, only when a source supplies one for this series.
    public let band: ClosedRange<Double>?
    public let bandLabel: String?
    public let summary: String

    public var id: Kind { kind }
    public var values: [Double?] { points.map { $0?.value } }
    public var hasData: Bool { points.contains { $0 != nil } }

    /// Runs of consecutive points. A missing day ends a run.
    public var segments: [[TrendPoint]] {
        var runs: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        for point in points {
            if let point {
                current.append(point)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}

/// Builds the trend charts from the shared training record and the merged daily metrics, so the weekly totals use
/// the same runs and sessions as Recent load (ADR-0035).
struct TrendCharts {
    /// What names a chart and formats its values.
    private struct Spec {
        let kind: TrendChart.Kind
        let title: String
        let unit: String
        let digits: Int
    }

    let calendar: Calendar
    let format: Format
    let settings: ReadinessRules.Settings

    func recovery(
        range: TrendRange, today: CalendarDay, metrics: [DailyMetrics], rawMetrics: [DailyMetrics],
        hrvSeries: HRVSeriesID?
    ) -> [TrendChart] {
        let days = (0..<range.days).map { today.adding(days: $0 - range.days + 1, calendar: calendar) }
        let byDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        var charts: [TrendChart] = []
        if let hrvSeries {
            let metric = hrvSeries.metric
            let plausible = settings.plausibleHRVMs
            let matching = rawMetrics.filter { entry in
                entry.sources.contains(metric.source) && entry.hrvWindow(metric) == hrvSeries.window
                    && entry.hrv(metric).map(plausible.contains) == true
            }
            let hrvByDay = Dictionary(matching.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
            let values = days.map { hrvByDay[$0]?.hrv(metric) }
            let label = hrvSeries.window == .daytime
                ? L10n.format("Daytime HRV ({1})", metric.seriesLabel)
                : L10n.format("HRV ({1})", metric.seriesLabel)
            charts.append(line(
                Spec(kind: .hrv, title: label, unit: "ms", digits: 0), range: range, days: days, values: values,
                band: hrvBand(hrvSeries, entry: days.reversed().lazy.compactMap { hrvByDay[$0] }.first)
            ))
        }
        let heartRate = settings.plausibleRestingHeartRate
        charts.append(line(
            Spec(kind: .restingHeartRate, title: L10n.text("Resting HR"), unit: "bpm", digits: 0),
            range: range, days: days,
            values: comparable(days, byDay, source: \.restingHeartRateOrigin) {
                $0.restingHeartRate.flatMap { heartRate.contains($0) ? $0 : nil }
            }
        ))
        let maxSleep = settings.maximumSleepHours
        charts.append(line(
            Spec(kind: .sleep, title: L10n.text("Sleep"), unit: "h", digits: 1), range: range, days: days,
            values: comparable(days, byDay, source: \.sleepOrigin) {
                $0.sleepSeconds.flatMap { $0 > 0 && $0 / 3_600 <= maxSleep ? $0 / 3_600 : nil }
            }
        ))
        return charts
    }

    func weekly(range: TrendRange, today: CalendarDay, record: TrainingRecord) -> [TrendChart] {
        let weeks = (range.days + 6) / 7
        let first = today.adding(days: 1 - range.days, calendar: calendar)
        let end = today.startDate(in: calendar)
        func week(of date: Date) -> Int? {
            let day = CalendarDay(date, calendar: calendar)
            guard (first...today).contains(day) else { return nil }
            let back = calendar.dateComponents([.day], from: day.startDate(in: calendar), to: end).day ?? 0
            return weeks - 1 - back / 7
        }
        var sets = [Double](repeating: 0, count: weeks)
        for session in record.sessions {
            guard let index = week(of: session.startedAt) else { continue }
            sets[index] += Double(session.entries.reduce(0) { $0 + $1.sets.filter(\.isWorking).count })
        }
        let setsSpec = Spec(kind: .strengthVolume, title: L10n.text("Strength sets per week"),
                            unit: L10n.text("sets"), digits: 0)
        var charts = [bars(setsSpec, range: range, today: today, values: sets)]
        if !record.runReadFailed {
            var distances = [Double](repeating: 0, count: weeks)
            for run in record.runs where run.distanceMeters.isFinite {
                if let index = week(of: run.startedAt) { distances[index] += run.distanceMeters / 1_000 }
            }
            let runSpec = Spec(kind: .runningDistance, title: L10n.text("Running distance per week"),
                               unit: "km", digits: 1)
            charts.append(bars(runSpec, range: range, today: today, values: distances))
        }
        return charts
    }

    // MARK: Lines

    /// Values of days whose source matches the latest reading's, so a source change never reads as a trend.
    private func comparable(
        _ days: [CalendarDay], _ byDay: [CalendarDay: DailyMetrics], source: KeyPath<DailyMetrics, DataSourceKind?>,
        value: (DailyMetrics) -> Double?
    ) -> [Double?] {
        var latest: DataSourceKind?
        for day in days.reversed() {
            if let metrics = byDay[day], value(metrics) != nil {
                latest = metrics[keyPath: source]
                break
            }
        }
        return days.map { day in
            guard let metrics = byDay[day], let number = value(metrics) else { return nil }
            let origin = metrics[keyPath: source]
            return origin == latest ? number : nil
        }
    }

    /// Garmin's own usual range, only for the RMSSD series it describes and when it reports one.
    private func hrvBand(_ series: HRVSeriesID, entry: DailyMetrics?) -> ClosedRange<Double>? {
        guard series.metric == .rmssd,
              let low = entry?.hrvBaselineLowMs, let high = entry?.hrvBaselineHighMs,
              settings.plausibleHRVMs.contains(low), settings.plausibleHRVMs.contains(high), low < high else {
            return nil
        }
        return low...high
    }

    private func line(
        _ spec: Spec, range: TrendRange, days: [CalendarDay], values: [Double?], band: ClosedRange<Double>? = nil
    ) -> TrendChart {
        let (kind, title, unit, digits) = (spec.kind, spec.title, spec.unit, spec.digits)
        let points = zip(days, values).map { day, value in
            value.map { TrendPoint(day: day.startDate(in: calendar), value: $0, label: dayText(day)) }
        }
        let present = points.compactMap { $0 }
        let amount = { (value: Double) in format.number(value, maxFractionDigits: digits) + " " + unit }
        let interval = L10n.format("Last {1} days", String(range.days))
        let summary: String
        if let last = present.last {
            let numbers = present.map(\.value)
            summary = L10n.format(
                "{1}, last {2} days: average {3}, from {4} to {5}, latest {6} on {7}. {8} of {9} days have a reading.",
                title, String(range.days), amount(numbers.reduce(0, +) / Double(numbers.count)),
                amount(numbers.min() ?? last.value), amount(numbers.max() ?? last.value), amount(last.value),
                last.label, String(present.count), String(range.days)
            )
        } else {
            summary = L10n.format("{1}: no readings in the last {2} days.", title, String(range.days))
        }
        let domain = days.first.flatMap { first in
            days.last.map { first.startDate(in: calendar)...$0.startDate(in: calendar) }
        }
        return TrendChart(
            kind: kind, style: .line, title: title, unit: unit, interval: interval, points: points,
            startLabel: days.first.map(dayText), endLabel: days.last.map(dayText),
            dateDomain: domain, partialWeekLabel: nil, band: band,
            bandLabel: band.map { _ in L10n.text("Garmin's usual range") }, summary: summary
        )
    }

    // MARK: Bars

    private func bars(_ spec: Spec, range: TrendRange, today: CalendarDay, values: [Double]) -> TrendChart {
        let (kind, title, unit, digits) = (spec.kind, spec.title, spec.unit, spec.digits)
        let weeks = values.count
        let partialDays = range.days % 7
        let points = values.enumerated().map { index, value in
            let offset = max(1 - range.days, 1 - (weeks - index) * 7)
            let start = today.adding(days: offset, calendar: calendar)
            return TrendPoint(day: start.startDate(in: calendar), value: value, label: dayText(start))
        }
        let amount = { (value: Double) in format.number(value, maxFractionDigits: digits) + " " + unit }
        let interval = L10n.format("Last {1} days", String(range.days))
        let fullWeeks = values.dropFirst(partialDays == 0 ? 0 : 1)
        let hasHistory = values.contains { $0 > 0 }
        let partialWeekLabel = hasHistory && partialDays > 0 ? L10n.format(
            "First bar covers {1} days: {2}.", String(partialDays), amount(values[0])
        ) : nil
        let summary: String
        if hasHistory {
            summary = L10n.format(
                "{1}, last {2} days: {3} in the latest week, {4} on average per full week, most {5} in a full week.",
                title, String(range.days), amount(fullWeeks.last ?? 0),
                amount(fullWeeks.reduce(0, +) / Double(fullWeeks.count)), amount(fullWeeks.max() ?? 0)
            )
        } else {
            summary = L10n.format("{1}: nothing recorded in the last {2} days.", title, String(range.days))
        }
        return TrendChart(
            kind: kind, style: .bars, title: title, unit: unit, interval: interval,
            points: hasHistory ? points.map(Optional.some) : [],
            startLabel: points.first?.label, endLabel: points.last?.label,
            dateDomain: nil, partialWeekLabel: partialWeekLabel,
            band: nil, bandLabel: nil, summary: summary
        )
    }

    private func dayText(_ day: CalendarDay) -> String {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
    }
}
