import Charts
import DesignSystem
import SwiftUI
import TrendsPresentation

struct PerformanceProgressView<Plan: View>: View {
    @Bindable var model: RecoveryProgressModel
    let plan: Plan
    @State private var runningKind: String?
    @State private var liftID: String?
    @State private var strengthMetric: String?

    init(model: RecoveryProgressModel, plan: Plan) {
        self.model = model
        self.plan = plan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                NavigationLink(destination: plan) {
                    Label("Plan progress and recovery history", systemImage: "calendar")
                }
                .frame(minHeight: 44)
                if model.showsPerformance {
                    Picker("Period", selection: $model.performanceRange) {
                        ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                    }
                    if model.hasRunningPerformance { running }
                    if model.hasStrengthPerformance { strength }
                }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var running: some View {
        let options = model.runningPerformance
        let selected = options.first { $0.id == runningKind }
            ?? options.first { !$0.points.isEmpty } ?? options.first
        return VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Running best times").font(.headline).accessibilityAddTraits(.isHeader)
            Picker("Distance", selection: $model.performanceDistance) {
                ForEach(PerformanceDistance.allCases) { Text($0.title).tag($0) }
            }
            if let selected {
                Picker("Run type", selection: selection($runningKind, default: selected.id)) {
                    ForEach(options) { Text($0.title).tag($0.id) }
                }
                PerformanceSeriesCard(series: selected)
            }
            comparableHeartRate
        }
    }

    private var comparableHeartRate: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Heart rate at comparable pace").font(.headline).accessibilityAddTraits(.isHeader)
            if let series = model.comparableHeartRate {
                PerformanceSeriesCard(series: series)
            } else {
                Text("Comparable heart rate needs steady segments with pace, terrain, conditions and sensor data.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
    }

    private var strength: some View {
        let lifts = model.strengthPerformanceOptions
        let lift = lifts.first { $0.id == liftID } ?? lifts.first
        let series = lift.map { model.strengthPerformance(for: $0) } ?? []
        let result = series.first { $0.id == strengthMetric } ?? series.first
        return VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Strength records").font(.headline).accessibilityAddTraits(.isHeader)
            if let lift {
                Picker("Lift", selection: selection($liftID, default: lift.id)) {
                    ForEach(lifts) { Text($0.title).tag($0.id) }
                }
                .onChange(of: liftID) { strengthMetric = nil }
                if let result {
                    Picker("Record", selection: selection($strengthMetric, default: result.id)) {
                        ForEach(series) { Text($0.title).tag($0.id) }
                    }
                    PerformanceSeriesCard(series: result)
                }
            } else {
                Text("No results in this period").foregroundStyle(.secondary)
            }
        }
    }

    private func selection(_ binding: Binding<String?>, default fallback: String) -> Binding<String> {
        Binding(get: { fallback }, set: { binding.wrappedValue = $0 })
    }
}

private struct PerformanceSeriesCard: View {
    let series: PerformanceSeries

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let best = series.best {
                AdaptiveStack(verticalAlignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(series.title).font(.headline)
                    Spacer()
                    Text(best.valueText).font(.title3.weight(.heavy)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            } else if series.points.isEmpty {
                Text("No results in this period").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(series.title).font(.headline)
            }
            Text(series.comparison).font(.subheadline).foregroundStyle(.secondary)
            if let context = series.context {
                Text(context).font(.subheadline).foregroundStyle(.secondary)
            }
            if let trend = series.trend {
                Text(trend).font(.subheadline)
            }
            if !series.points.isEmpty {
                chart
                DisclosureGroup("View sessions") {
                    ForEach(series.points.reversed()) { point in
                        NavigationLink(value: point.id) {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(point.date, format: .dateTime.day().month().year().hour().minute())
                                Text(point.valueText).fontWeight(.semibold)
                                Text(point.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: Radius.card))
    }

    private var chart: some View {
        Chart(series.points) { point in
            PointMark(
                x: .value("Date", point.date),
                y: .value("Result", point.value)
            )
            .symbol(series.isEstimated ? BasicChartSymbolShape.diamond : .circle)
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month())
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let bounds = geometry[plotFrame]
                    ForEach(series.points) { point in
                        if let position = proxy.position(for: (x: point.date, y: point.value)) {
                            NavigationLink(value: point.id) {
                                Color.clear.frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .position(x: bounds.minX + position.x, y: bounds.minY + position.y)
                        }
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }
}
