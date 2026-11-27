import Charts
import DesignSystem
import SwiftUI
import TrendsPresentation

struct PerformanceProgressView<Plan: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
                if let note = model.trainingReadNote {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Label(note, systemImage: "exclamationmark.triangle")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Try again") { Task { await model.load() } }
                                .frame(minHeight: 44)
                                .disabled(model.isLoading)
                        }
                    }
                }
                if model.showsPerformance {
                    periodPicker
                    if model.hasStrengthPerformance { strength }
                    if model.hasRunningPerformance { running }
                } else if !model.hasLoaded {
                    LoadingState("Loading…")
                } else if model.trainingReadNote == nil {
                    ListEmptyState(title: "No data yet", systemImage: "chart.line.uptrend.xyaxis")
                }
                planLink
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var periodPicker: some View {
        let picker = Picker("Period", selection: $model.performanceRange) {
            ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
        }
        return Group {
            if typeSize.isAccessibilitySize {
                picker.pickerStyle(.menu).frame(minHeight: 44)
            } else {
                picker.pickerStyle(.segmented)
            }
        }
    }

    private var planLink: some View {
        NavigationLink(destination: plan) {
            Card(radius: Radius.tile) {
                HStack(spacing: Spacing.medium) {
                    Image(systemName: "calendar").foregroundStyle(.tint).accessibilityHidden(true)
                    Text("Plan progress and recovery history").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var running: some View {
        let options = model.runningPerformance
        let selected = options.first { $0.id == runningKind }
            ?? options.first { !$0.points.isEmpty } ?? options.first
        return VStack(alignment: .leading, spacing: Spacing.small) {
            SectionHeader(Text("Running"))
            Card {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    SectionHeader(Text("Running best times"))
                    Picker("Distance", selection: $model.performanceDistance) {
                        ForEach(PerformanceDistance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(minHeight: 44)
                    if let selected {
                        metricPicker("Run type", options: options, selected: selected, binding: $runningKind)
                        PerformanceSeriesContent(series: selected, showsTitle: false)
                    }
                }
            }
            Card {
                DisclosureGroup("Heart rate at comparable pace") {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        if let series = model.comparableHeartRate {
                            PerformanceSeriesContent(series: series)
                        } else {
                            Text("Compare steady blocks from both periods using the same heart-rate sensor.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        sensorConfirmation
                    }
                    .padding(.top, Spacing.small)
                }
            }
        }
    }

    private var sensorConfirmation: some View {
        let pending = model.pendingPulseSensorRows
        let confirmed = model.confirmedPulseSensorRows
        return VStack(alignment: .leading, spacing: Spacing.small) {
            if !pending.isEmpty {
                DisclosureGroup("Confirm heart-rate sensors") {
                    Text("Group runs only when you used the same watch or chest strap.")
                        .font(.footnote).foregroundStyle(.secondary)
                    sensorRows(pending)
                }
            }
            if !confirmed.isEmpty {
                DisclosureGroup("Confirmed sensors") {
                    sensorRows(confirmed)
                }
            }
        }
    }

    private func sensorRows(_ rows: [RunningPulseSensorRow]) -> some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                NavigationLink(value: PerformanceSession.run(row.run)) {
                    Text(row.title)
                }
                Text(row.run.startedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.footnote)
                Picker("Heart-rate sensor", selection: Binding(
                    get: { row.selection }, set: { model.choosePulseSensor($0, for: row.id) }
                )) {
                    ForEach(RunningPulseSensor.allCases) { sensor in
                        Text(sensor.title).tag(sensor)
                    }
                }
                .frame(minHeight: 44)
            }
            .padding(.vertical, Spacing.xSmall)
        }
    }

    private var strength: some View {
        let lifts = model.strengthPerformanceOptions
        let lift = lifts.first { $0.id == liftID } ?? lifts.first
        let series = lift.map { model.strengthPerformance(for: $0) } ?? []
        let result = series.first { $0.id == strengthMetric } ?? series.first
        return VStack(alignment: .leading, spacing: Spacing.small) {
            SectionHeader(Text("Strength"))
            Card {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    if let lift, let result {
                        Menu {
                            Picker("Lift", selection: selection($liftID, default: lift.id)) {
                                ForEach(lifts) { Text($0.title).tag($0.id) }
                            }
                        } label: {
                            selectorLabel(lift.title, font: .title3.weight(.semibold))
                        }
                        .accessibilityLabel(Text("Lift"))
                        .accessibilityValue(Text(lift.title))
                        .onChange(of: liftID) { strengthMetric = nil }

                        metricPicker("Record", options: series, selected: result, binding: $strengthMetric)
                        PerformanceSeriesContent(series: result, showsTitle: false)
                    } else {
                        Text("No results in this period").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func metricPicker(
        _ label: LocalizedStringKey, options: [PerformanceSeries], selected: PerformanceSeries,
        binding: Binding<String?>
    ) -> some View {
        Menu {
            Picker(label, selection: selection(binding, default: selected.id)) {
                ForEach(options) { Text($0.title).tag($0.id) }
            }
        } label: {
            selectorLabel(selected.title, font: .subheadline.weight(.semibold))
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(selected.title))
    }

    private func selectorLabel(_ title: String, font: Font) -> some View {
        HStack(spacing: Spacing.small) {
            Text(title).font(font).multilineTextAlignment(.leading)
            Spacer(minLength: Spacing.small)
            Image(systemName: "chevron.up.chevron.down").font(.footnote).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func selection(_ binding: Binding<String?>, default fallback: String) -> Binding<String> {
        Binding(get: { fallback }, set: { binding.wrappedValue = $0 })
    }
}

private struct PerformanceSeriesContent: View {
    let series: PerformanceSeries
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if showsTitle {
                    SectionHeader(Text(series.title))
                }
                if let best = series.best {
                    Text(best.valueText).font(.title.weight(.heavy)).monospacedDigit()
                    if let source = best.sourceName {
                        Text(source).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if series.points.isEmpty {
                Text("No results in this period").font(.subheadline).foregroundStyle(.secondary)
            } else if series.resultKind != .recorded {
                Label(series.resultKind.title, systemImage: resultSymbolName)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let context = series.context {
                Text(context).font(.subheadline).foregroundStyle(.secondary)
            }
            if let trend = series.trend {
                Text(trend).font(.subheadline)
            }
            if !series.points.isEmpty {
                chart
            }
            Text(series.comparison).font(.footnote).foregroundStyle(.secondary)
            if !series.points.isEmpty {
                Divider()
                DisclosureGroup("View sessions") {
                    ForEach(series.points.reversed()) { point in
                        NavigationLink(value: point.id) {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(point.date, format: .dateTime.day().month().year().hour().minute())
                                Text(point.valueText).fontWeight(.semibold)
                                Text(point.detail).font(.subheadline).foregroundStyle(.secondary)
                                if let source = point.sourceName {
                                    Text(source).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private var resultSymbolName: String {
        switch series.resultKind {
        case .recorded: "circle.fill"
        case .estimated: "diamond.fill"
        case .upperBound: "triangle.fill"
        }
    }

    private var resultSymbol: BasicChartSymbolShape {
        switch series.resultKind {
        case .recorded: .circle
        case .estimated: .diamond
        case .upperBound: .triangle
        }
    }

    private var chart: some View {
        Chart(series.points) { point in
            let mark = PointMark(
                x: .value("Date", point.date),
                y: .value("Result", point.value)
            )
            .accessibilityLabel(Text(point.date, format: .dateTime.day().month().year()))
            .accessibilityValue(Text([point.valueText, point.sourceName].compactMap { $0 }.joined(separator: ", ")))
            if series.hasMultipleSources, let source = point.sourceName {
                mark
                    .foregroundStyle(by: .value("Source", source))
                    .symbol(by: .value("Source", source))
            } else {
                mark.symbol(resultSymbol).foregroundStyle(Color.accentColor)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { axis in
                AxisGridLine()
                if let value = axis.as(Double.self) {
                    AxisValueLabel { Text(series.axisLabel(value)) }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
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
                            .accessibilityHidden(true)
                            .position(x: bounds.minX + position.x, y: bounds.minY + position.y)
                        }
                    }
                }
            }
        }
        .frame(height: 215)
    }
}
