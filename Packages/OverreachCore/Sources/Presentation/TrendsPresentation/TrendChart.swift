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
    /// Whole weeks in the interval: weekly totals cover these, ending today.
    var weeks: Int { rawValue / 7 }
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
    /// "Last 30 days" or "Last 12 weeks".
    public let interval: String
    /// Lines: runs of consecutive days, so a day without a reading is a visible break. Bars: one run of weeks.
    public let segments: [[TrendPoint]]
    /// A personal reference band, only when a source supplies one for this series.
    public let band: ClosedRange<Double>?
    public let bandLabel: String?
    public let summary: String

    public var id: Kind { kind }
    public var hasData: Bool { segments.contains { !$0.isEmpty } }
}

/// Builds the trend charts from the shared training record and the merged daily metrics, so the weekly totals use
/// the same runs and sessions as Recent load (ADR-0035).
struct TrendCharts {
    let calendar: Calendar
    let format: Format
    let settings: ReadinessRules.Settings

    func recovery(
        range: TrendRange, today: CalendarDay, metrics: [DailyMetrics], hrvSeries: HRVSeriesID?
    ) -> [TrendChart] {
        let days = (0..<range.days).map { today.adding(days: $0 - range.days + 1, calendar: calendar) }
        let byDay = Dictionary(metrics.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        var charts: [TrendChart] = []
        if let hrvSeries {
            let plausible = settings.plausibleHRVMs
            let usable = { (value: Double?) -> Double? in value.flatMap { plausible.contains($0) ? $0 : nil } }
            let label = L10n.format("HRV ({1})", hrvSeries.metric.seriesLabel)
            let values = days.map { (day: CalendarDay) -> Double? in
                guard let entry = byDay[day], entry.hrvWindow(hrvSeries.metric) == hrvSeries.window else { return nil }
                return usable(entry.hrv(hrvSeries.metric))
            }
            charts.append(line(
                .hrv, title: label, unit: "ms", digits: 0, range: range, days: days, values: values,
                band: hrvBand(hrvSeries, byDay: byDay, days: days)
            ))
        }
        let heartRate = settings.plausibleRestingHeartRate
        charts.append(line(
            .restingHeartRate, title: L10n.text("Resting HR"), unit: "bpm", digits: 0, range: range, days: days,
            values: comparable(days, byDay, source: \.restingHeartRateSource) {
                $0.restingHeartRate.flatMap { heartRate.contains($0) ? $0 : nil }
            }
        ))
        let maxSleep = settings.maximumSleepHours
        charts.append(line(
            .sleep, title: L10n.text("Sleep"), unit: "h", digits: 1, range: range, days: days,
            values: comparable(days, byDay, source: \.sleepSource) {
                $0.sleepSeconds.flatMap { $0 > 0 && $0 / 3_600 <= maxSleep ? $0 / 3_600 : nil }
            }
        ))
        return charts
    }

    func weekly(range: TrendRange, today: CalendarDay, record: TrainingRecord) -> [TrendChart] {
        let weeks = range.weeks
        func week(of date: Date) -> Int? {
            let day = CalendarDay(date, calendar: calendar)
            let first = today.adding(days: -(weeks * 7 - 1), calendar: calendar)
            guard (first...today).contains(day) else { return nil }
            let start = day.startDate(in: calendar), end = today.startDate(in: calendar)
            let back = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            return weeks - 1 - back / 7
        }
        var sets = [Double](repeating: 0, count: weeks)
        for session in record.sessions {
            guard let index = week(of: session.startedAt) else { continue }
            sets[index] += Double(session.entries.reduce(0) { $0 + $1.sets.filter(\.isWorking).count })
        }
        var charts = [bars(
            .strengthVolume, title: L10n.text("Strength sets per week"), unit: L10n.text("sets"), digits: 0,
            range: range, today: today, values: sets, hasHistory: !record.sessions.isEmpty
        )]
        if !record.runReadFailed {
            var km = [Double](repeating: 0, count: weeks)
            for run in record.runs where run.distanceMeters.isFinite {
                if let index = week(of: run.startedAt) { km[index] += run.distanceMeters / 1_000 }
            }
            charts.append(bars(
                .runningDistance, title: L10n.text("Running distance per week"), unit: "km", digits: 1,
                range: range, today: today, values: km, hasHistory: !record.runs.isEmpty
            ))
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
            return origin == nil || origin == latest ? number : nil
        }
    }

    /// Garmin's own usual range, only for the RMSSD series it describes and when it reports one.
    private func hrvBand(
        _ series: HRVSeriesID, byDay: [CalendarDay: DailyMetrics], days: [CalendarDay]
    ) -> ClosedRange<Double>? {
        guard series.metric == .rmssd,
              let entry = days.reversed().compactMap({ byDay[$0] }).first(where: { $0.hrv(.rmssd) != nil }),
              let low = entry.hrvBaselineLowMs, let high = entry.hrvBaselineHighMs, low < high else { return nil }
        return low...high
    }

    private func line(
        _ kind: TrendChart.Kind, title: String, unit: String, digits: Int, range: TrendRange, days: [CalendarDay],
        values: [Double?], band: ClosedRange<Double>? = nil
    ) -> TrendChart {
        var segments: [[TrendPoint]] = []
        var current: [TrendPoint] = []
        var present: [(day: CalendarDay, value: Double)] = []
        for (day, value) in zip(days, values) {
            guard let value else {
                if !current.isEmpty { segments.append(current) }
                current = []
                continue
            }
            current.append(TrendPoint(day: day.startDate(in: calendar), value: value, label: dayText(day)))
            present.append((day, value))
        }
        if !current.isEmpty { segments.append(current) }
        let amount = { (value: Double) in format.number(value, maxFractionDigits: digits) + " " + unit }
        let interval = L10n.format("Last {1} days", String(range.days))
        let summary: String
        if let last = present.last {
            let numbers = present.map(\.value)
            summary = L10n.format(
                "{1}, last {2} days: average {3}, from {4} to {5}, latest {6} on {7}. {8} of {9} days have a reading.",
                title, String(range.days), amount(numbers.reduce(0, +) / Double(numbers.count)),
                amount(numbers.min() ?? last.value), amount(numbers.max() ?? last.value), amount(last.value),
                dayText(last.day), String(present.count), String(range.days)
            )
        } else {
            summary = L10n.format("{1}: no readings in the last {2} days.", title, String(range.days))
        }
        return TrendChart(
            kind: kind, style: .line, title: title, unit: unit, interval: interval, segments: segments, band: band,
            bandLabel: band.map { _ in L10n.text("Garmin's usual range") }, summary: summary
        )
    }

    // MARK: Bars

    private func bars(
        _ kind: TrendChart.Kind, title: String, unit: String, digits: Int, range: TrendRange, today: CalendarDay,
        values: [Double], hasHistory: Bool
    ) -> TrendChart {
        let weeks = values.count
        let points = values.enumerated().map { index, value in
            let start = today.adding(days: -(weeks - index) * 7 + 1, calendar: calendar)
            return TrendPoint(day: start.startDate(in: calendar), value: value, label: dayText(start))
        }
        let amount = { (value: Double) in format.number(value, maxFractionDigits: digits) + " " + unit }
        let total = values.reduce(0, +)
        let summary: String
        if total > 0 {
            summary = L10n.format(
                "{1}, last {2} weeks: {3} in the latest week, {4} on average, most {5}.", title, String(weeks),
                amount(values.last ?? 0), amount(total / Double(weeks)), amount(values.max() ?? 0)
            )
        } else {
            summary = L10n.format("{1}: nothing recorded in the last {2} weeks.", title, String(weeks))
        }
        return TrendChart(
            kind: kind, style: .bars, title: title, unit: unit, interval: L10n.format("Last {1} weeks", String(weeks)),
            segments: hasHistory || total > 0 ? [points] : [], band: nil, bandLabel: nil, summary: summary
        )
    }

    private func dayText(_ day: CalendarDay) -> String {
        let style = Date.FormatStyle(locale: format.locale, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.day().month(.abbreviated))
    }
}
