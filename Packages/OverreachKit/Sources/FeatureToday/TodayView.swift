import DesignSystem
import Domain
import SwiftUI
import TodayPresentation

/// "How should I train today?" — readiness, key recovery metrics and (phase 3) today's proposed session.
public struct TodayView: View {
    @State private var model: TodayModel

    public init(model: TodayModel) {
        _model = State(initialValue: model)
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.medium)]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    StatusBadge(title: model.readinessTitle, tone: model.readinessLevel.tone)

                    LazyVGrid(columns: columns, spacing: Spacing.medium) {
                        MetricTile(title: "Sleep", value: model.sleepHours, unit: "h", fractionDigits: 1,
                                   caption: model.sleepCaption ?? model.sleepAverageCaption)
                        MetricTile(title: "HRV", value: model.hrvMs, unit: "ms", caption: model.hrvCaption)
                        MetricTile(title: "Resting HR", value: model.restingHeartRate, unit: "bpm",
                                   caption: model.restingHeartRateCaption)
                        MetricTile(title: "Steps", value: model.steps, unit: "", caption: model.stepsCaption)
                        if model.showsBodyBattery {
                            MetricTile(title: "Body Battery", value: model.bodyBattery, unit: "")
                        }
                        if model.showsVO2Max {
                            MetricTile(title: "VO2max", value: model.vo2Max, unit: "", fractionDigits: 1)
                        }
                    }

                    if let sources = model.sourcesText {
                        Text(sources).font(.caption).foregroundStyle(.secondary)
                    }

                    if model.showsConnectHealth {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Button("Connect Apple Health", systemImage: "heart.text.square") {
                                Task { await model.connectHealth() }
                            }
                            .buttonStyle(.borderedProminent)
                            Text(
                                """
                                Sleep, HRV, resting heart rate and steps come from Apple Health: from an Apple Watch, \
                                from Garmin Connect (turn on Apple Health in its settings) or from the iPhone itself. \
                                If you already allowed it, check Health → Sharing → Apps → Overreach.
                                """
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            if let error = model.accessError {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
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
            .task { await model.load() }
            .refreshable { await model.load() }
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

#Preview {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource()]))
}
#endif
