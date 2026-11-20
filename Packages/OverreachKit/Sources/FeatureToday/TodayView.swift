import DesignSystem
import Domain
import PresentationKit
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
                    if model.showsReadinessCard {
                        readiness
                    }
                    if let option = model.strengthOption {
                        easyStrength(option)
                    }
                    if model.showsCheckIn {
                        checkIn
                    }
                    if model.showsTrainingTimeline {
                        recentTraining
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
            if let summary = model.readinessSummary {
                Text(summary).font(.subheadline)
            }
            if model.showsReadinessDetails {
                DisclosureGroup("Why this recommendation?") {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        ForEach(model.readinessLines, id: \.self) { line in
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(line.text).font(.subheadline)
                                if let source = line.source {
                                    Text(line.evidence).font(.caption).foregroundStyle(.secondary)
                                    Link("Research source", destination: source).font(.caption)
                                }
                                ReadingLinks(items: line.readings.map(ReadingLinkItem.init))
                            }
                        }
                        ForEach(model.readinessContext, id: \.self) { text in
                            Text(text).font(.subheadline)
                        }
                        if let context = model.readinessTrainingContext {
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(context.heading).font(.subheadline.weight(.medium))
                                ForEach(context.workouts.indices, id: \.self) { index in
                                    Text(context.workouts[index]).font(.subheadline)
                                }
                            }
                        }
                        if let note = model.hrvCoverageNote {
                            Text(note).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.small)
                }
            }
        }
    }

    private func easyStrength(_ option: StrengthOption) -> some View {
        DisclosureGroup("If you want to lift today") {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if let heading = option.heading {
                    Text(heading).font(.subheadline)
                }
                ForEach(option.exerciseRows) { row in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Text(row.reference).foregroundStyle(.secondary)
                        Text(row.suggestion)
                    }
                    .font(.subheadline)
                }
                Text(option.guidance).font(.subheadline)
                Text(option.evidence).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.small)
        }
    }

    private var recentTraining: some View {
        DisclosureGroup("Recent training and recovery") {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                if let note = model.trainingTimelineNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(model.recentTrainingDays) { day in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(day.date).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                        if let recovery = day.recovery {
                            Text(recovery).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(day.workouts.enumerated()), id: \.offset) { _, workout in
                            Text(workout).font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.small)
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
                    MetricTile(title: "Body Battery", value: model.bodyBattery, unit: "",
                               caption: model.bodyBatteryCaption)
                }
                if model.showsStress {
                    MetricTile(title: "Stress", value: model.stress, unit: "", caption: model.stressCaption)
                }
                if model.showsVO2Max {
                    MetricTile(title: "VO2max", value: model.vo2Max, unit: "", fractionDigits: 1,
                               caption: model.vo2MaxCaption)
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
        let calendar = Calendar.current
        return (0...25).map { offset in
            let day = range.upperBound.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.hrvRMSSDMs = offset < 4 ? 34 : 43
            metrics.restingHeartRate = offset == 0 ? 60 : 59
            if offset == 0 {
                metrics.sleepSeconds = 7.6 * 3_600
                metrics.bodyBatteryHigh = 64
            }
            return metrics
        }.filter { range.contains($0.day) }
    }

    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        [RunActivity(id: kind.rawValue, source: kind, startedAt: end.addingTimeInterval(-25 * 3_600),
                     durationSeconds: 1_800, distanceMeters: 5_000, averageHeartRate: 145)]
    }
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

extension ReadingLinkItem {
    /// The display values of a curated reading (ADR-0027).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
