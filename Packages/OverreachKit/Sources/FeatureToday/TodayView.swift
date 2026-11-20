import DesignSystem
import Domain
import SwiftUI
import TodayPresentation

/// "How should I train today?" — readiness, key recovery metrics and (phase 3) today's proposed session.
public struct TodayView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: TodayModel
    @State private var checkInSheet: CheckInModel?
    private let onConnectGarmin: () -> Void

    /// - Parameter onConnectGarmin: opens the Garmin setup (wired by the App: it belongs to Settings).
    public init(model: TodayModel, onConnectGarmin: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.onConnectGarmin = onConnectGarmin
    }

    private var columns: [GridItem] {
        [GridItem(typeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 150), spacing: Spacing.medium)]
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    if model.showsConnectHealth {
                        connectHealth
                    }
                    if model.readinessLevel != .unknown {
                        readiness
                    }
                    if model.showsCheckIn {
                        checkIn
                    }
                    if model.showsMetrics {
                        metrics
                    }

                    if model.showsConnectGarmin {
                        Button(action: onConnectGarmin) {
                            FeatureHighlightRow(
                                symbol: "applewatch.radiowaves.left.and.right", title: Text("Connect your Garmin"),
                                detail: Text(
                                    "Nightly HRV, sleep score and Body Battery for the readiness light. Three steps."
                                )
                            )
                            .padding(Spacing.medium)
                            .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
                        }
                        .buttonStyle(.plain)
                    }

                    if model.showsSourceWarning {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Label("Some sources could not be updated.", systemImage: "exclamationmark.triangle")
                            if let detail = model.sourceWarningDetail {
                                Text(detail).textSelection(.enabled)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Today")
            .overlay {
                if model.showsLoadingIndicator {
                    ProgressView()
                }
            }
            .sheet(item: $checkInSheet) { sheet in
                CheckInView(model: sheet) { Task { await model.load() } }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    private var connectHealth: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button("Connect Apple Health", systemImage: "heart.text.square") {
                Task { await model.connectHealth() }
            }
            .buttonStyle(BrandButtonStyle())

            DisclosureGroup("About Apple Health data") {
                Text("""
                    Sleep, HRV, resting heart rate and steps come from Apple Health: from an Apple Watch, \
                    from Garmin Connect (turn on Apple Health in its settings) or from the iPhone itself. \
                    If you already allowed it, check Health → Sharing → Apps → Overreach.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, Spacing.xSmall)
            }
            if let error = model.accessError {
                StatusLabel(title: error, tone: .critical)
                    .font(.footnote)
            }
        }
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            StatusBadge(title: model.readinessTitle, tone: model.readinessLevel.tone)
            Text(model.readinessAdvice).font(.headline)
            if !model.readinessLines.isEmpty {
                DisclosureGroup("Why this recommendation?") {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        ForEach(model.readinessLines, id: \.self) { line in
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(line.text).font(.subheadline)
                                Text(line.evidence).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.small)
                }
            }
        }
    }

    private var checkIn: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Button(model.checkInButtonTitle, systemImage: "face.smiling") {
                checkInSheet = model.makeCheckInModel()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if let summary = model.checkInSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Today's metrics")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: Spacing.medium) {
                if model.showsSleep {
                    MetricTile(title: "Sleep", value: model.sleepHours, unit: "h", fractionDigits: 1,
                               caption: model.sleepCaption ?? model.sleepAverageCaption)
                }
                if model.showsHRV {
                    MetricTile(title: "HRV", value: model.hrvMs, unit: "ms", caption: model.hrvCaption)
                }
                if model.showsRestingHeartRate {
                    MetricTile(title: "Resting HR", value: model.restingHeartRate, unit: "bpm",
                               caption: model.restingHeartRateCaption)
                }
                if model.showsSteps {
                    MetricTile(title: "Steps", value: model.steps, unit: "", caption: model.stepsCaption)
                }
                if model.showsBodyBattery {
                    MetricTile(title: "Body Battery", value: model.bodyBattery, unit: "")
                }
                if model.showsStress {
                    MetricTile(title: "Stress", value: model.stress, unit: "")
                }
                if model.showsVO2Max {
                    MetricTile(title: "VO2max", value: model.vo2Max, unit: "", fractionDigits: 1)
                }
            }

            if let sources = model.sourcesText {
                Text(sources).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension ReadinessLevel {
    /// How each level looks on this screen.
    var tone: StatusTone {
        switch self {
        case .green: .positive
        case .amber: .caution
        case .red: .critical
        case .unknown: .neutral
        }
    }
}

#if DEBUG
/// Sample data for previews.
struct PreviewMetricsSource: MetricsSource {
    let kind: DataSourceKind = .garmin

    func isAvailable() async -> Bool { true }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        var metrics = DailyMetrics(day: range.upperBound, sources: [.garmin])
        metrics.hrvNightlyAverageMs = 37
        metrics.restingHeartRate = 54
        metrics.sleepSeconds = 6.4 * 3600
        metrics.bodyBatteryHigh = 58
        return [metrics]
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

#Preview("Recovery metrics") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource()]))
}

#Preview("Large text in dark mode") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource()]))
        .environment(\.dynamicTypeSize, .accessibility3)
        .preferredColorScheme(.dark)
}
#endif
