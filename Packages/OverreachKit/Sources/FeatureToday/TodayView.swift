import DesignSystem
import Domain
import SwiftUI

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
                    ReadinessBadge(readiness: model.readiness)

                    LazyVGrid(columns: columns, spacing: Spacing.medium) {
                        MetricTile(title: "HRV", value: model.metrics?.hrvNightlyAverageMs, unit: "ms")
                        MetricTile(title: "Resting HR", value: model.metrics?.restingHeartRate, unit: "bpm")
                        MetricTile(
                            title: "Sleep",
                            value: model.metrics?.sleepSeconds.map { $0 / 3600 },
                            unit: "h",
                            fractionDigits: 1
                        )
                        MetricTile(title: "Body Battery", value: model.metrics?.bodyBatteryHigh, unit: "")
                    }

                    if !model.failedSources.isEmpty {
                        Label("Some sources could not be updated.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Today")
            .overlay {
                if model.isLoading && model.metrics == nil {
                    ProgressView()
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
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
