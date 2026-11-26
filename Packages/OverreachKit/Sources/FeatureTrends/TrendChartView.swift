import DesignSystem
import SwiftUI
import TrendsPresentation

// Views only: the series, units, intervals and the spoken summary come from `TrendsPresentation` (ADR-0014).

/// The interval picker and the charts of one detail. The summary under each chart carries the takeaway and the key
/// values; VoiceOver reads it instead of the plot.
struct TrendSection: View {
    let model: RecoveryProgressModel
    let charts: [TrendChart]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Trends").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                intervalPicker.pickerStyle(.menu)
            } else {
                intervalPicker.pickerStyle(.segmented)
            }
            ForEach(charts) { chart in
                TrendChartView(chart: chart)
            }
        }
    }

    private var intervalPicker: some View {
        Picker("Interval", selection: Binding(
            get: { model.trendRange },
            set: { model.selectTrendRange($0) }
        )) {
            ForEach(TrendRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
    }
}

private struct TrendChartView: View {
    let chart: TrendChart

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text(chart.title)) {
                    Text(chart.unit).font(.caption).foregroundStyle(.secondary)
                }
                Text(chart.interval).font(.caption).foregroundStyle(.secondary)
                SignalTrendChart(
                    values: chart.values, band: chart.band, tone: .caution,
                    style: chart.style == .bars ? .bars : .line, size: .full,
                    startLabel: chart.startLabel, endLabel: chart.endLabel
                )
                if let label = chart.bandLabel, SignalTrendChart.hasData(chart.values) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Text(chart.summary).font(.subheadline).foregroundStyle(.secondary)
                if let note = chart.partialWeekLabel {
                    Text(note).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([chart.summary, chart.partialWeekLabel].compactMap { $0 }.joined(separator: " ")))
    }
}
