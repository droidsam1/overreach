import Charts
import DesignSystem
import SwiftUI
import TrendsPresentation

// Views only: the series, units, intervals and the spoken summary come from `TrendsPresentation` (ADR-0014).

/// The interval picker and the charts of one detail. The summary under each chart carries the takeaway and the key
/// values; VoiceOver reads it instead of the plot.
struct TrendSection: View {
    let model: RecoveryProgressModel
    let charts: [TrendChart]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Trends").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Picker("Interval", selection: Binding(
                get: { model.trendRange },
                set: { model.selectTrendRange($0) }
            )) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            ForEach(charts) { chart in
                TrendChartView(chart: chart)
            }
        }
    }
}

private struct TrendChartView: View {
    let chart: TrendChart

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(chart.title).font(.headline)
                Spacer()
                Text(chart.unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(chart.interval).font(.caption).foregroundStyle(.secondary)
            if chart.hasData {
                plot.frame(height: 160).accessibilityHidden(true)
            }
            if let label = chart.bandLabel, chart.band != nil {
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text(chart.summary).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(chart.title))
        .accessibilityValue(Text(chart.summary))
    }

    private var plot: some View {
        Chart {
            if let band = chart.band {
                RuleMark(y: .value("Usual low", band.lowerBound))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                RuleMark(y: .value("Usual high", band.upperBound))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(Array(chart.segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment, id: \.day) { point in
                    if chart.style == .bars {
                        BarMark(x: .value("Week starting", point.label), y: .value(chart.title, point.value))
                    } else {
                        LineMark(
                            x: .value("Day", point.day, unit: .day), y: .value(chart.title, point.value),
                            series: .value("Run", index)
                        )
                        PointMark(x: .value("Day", point.day, unit: .day), y: .value(chart.title, point.value))
                            .symbolSize(20)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: chart.style == .bars))
    }
}
