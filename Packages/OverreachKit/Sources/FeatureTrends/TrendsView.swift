import DesignSystem
import PresentationKit
import SwiftUI
import TrendsPresentation

/// "Recovery & Progress": one row per section with a short summary, each opening its detail. Today's "View
/// recovery" opens the recovery detail and Plan's "View progress" the progress detail directly. Pushed inside the
/// caller's navigation stack, so going back keeps the caller in context.
public struct TrendsView<Progress: View>: View {
    @State private var model: RecoveryProgressModel
    private let section: RecoveryProgressModel.Section?
    private let progressSummary: String
    private let progress: Progress
    private let onConnectGarmin: () -> Void

    /// - Parameters:
    ///   - section: open this section's detail instead of the list of sections.
    ///   - progressSummary: the line under the Progress row.
    ///   - progress: the Progress detail. It comes from the Plan feature, so the app wires it.
    public init(
        model: RecoveryProgressModel, section: RecoveryProgressModel.Section? = nil, progressSummary: String = "",
        onConnectGarmin: @escaping () -> Void = {}, @ViewBuilder progress: () -> Progress
    ) {
        _model = State(initialValue: model)
        self.section = section
        self.progressSummary = progressSummary
        self.progress = progress()
        self.onConnectGarmin = onConnectGarmin
    }

    public var body: some View {
        Group {
            switch section {
            case .recovery: RecoveryDetail(model: model, onConnectGarmin: onConnectGarmin, linksToRecentLoad: true)
            case .recentLoad: RecentLoadDetail(model: model, onConnectGarmin: onConnectGarmin)
            case .progress:
                PerformanceProgressView(model: model, plan: progress)
            case nil: sections
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        await model.load()
        if section == nil { updateSectionHints() }
    }

    private func updateSectionHints() {
        model.updateSectionHints(includesProgress: Progress.self != EmptyView.self)
    }

    private var sections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                SourceStatus(model: model, onConnectGarmin: onConnectGarmin)
                ForEach(model.newSectionHints, id: \.self) { hint in
                    Text(hint).font(.subheadline).foregroundStyle(.secondary)
                }
                if model.showsRecovery {
                    NavigationLink(destination: RecoveryDetail(model: model, onConnectGarmin: onConnectGarmin)) {
                        SectionRow(
                            title: "Recovery", systemImage: "heart.text.square", summary: model.recoverySummary
                        )
                    }
                }
                RecentLoadLink(model: model, onConnectGarmin: onConnectGarmin)
                if model.showsProgress, Progress.self != EmptyView.self {
                    NavigationLink(destination: PerformanceProgressView(model: model, plan: progress)) {
                        SectionRow(
                            title: "Progress", systemImage: "chart.line.uptrend.xyaxis", summary: progressSummary
                        )
                    }
                }
                if let hint = model.unlockHint {
                    ListEmptyState(title: "No data yet", systemImage: "chart.xyaxis.line", description: Text(hint))
                }
            }
            .buttonStyle(.plain)
            .padding(Spacing.medium)
        }
        .onChange(of: model.sectionHintCandidates) { updateSectionHints() }
        .navigationTitle("Recovery & Progress")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

extension TrendsView where Progress == EmptyView {
    public init(
        model: RecoveryProgressModel, section: RecoveryProgressModel.Section? = nil,
        onConnectGarmin: @escaping () -> Void = {}
    ) {
        self.init(model: model, section: section, onConnectGarmin: onConnectGarmin) { EmptyView() }
    }
}

private struct RecentLoadLink: View {
    let model: RecoveryProgressModel
    let onConnectGarmin: () -> Void

    var body: some View {
        if model.showsRecentLoad {
            NavigationLink(destination: RecentLoadDetail(model: model, onConnectGarmin: onConnectGarmin)) {
                SectionRow(title: "Recent load", systemImage: "chart.bar", summary: model.recentLoadSummary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SectionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let summary: String

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: systemImage).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(title).font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.tile))
        .accessibilityElement(children: .combine)
    }
}

/// A source that failed, a workout read that failed and the way to retry or connect, shown above the data that did
/// load.
private struct SourceStatus: View {
    let model: RecoveryProgressModel
    let onConnectGarmin: () -> Void

    var body: some View {
        if model.showsFailure || model.trainingReadNote != nil {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if model.showsFailure {
                    Label("Some sources could not be updated.", systemImage: "exclamationmark.triangle")
                    ForEach(model.failureLines, id: \.self) { Text($0).textSelection(.enabled) }
                }
                if let note = model.trainingReadNote {
                    Label(note, systemImage: "exclamationmark.triangle")
                }
                Button("Try again", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoading)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if model.showsConnectGarmin {
            Button("Connect your Garmin", systemImage: "applewatch.radiowaves.left.and.right", action: onConnectGarmin)
                .buttonStyle(.bordered)
        }
    }
}

private struct RecoveryDetail: View {
    let model: RecoveryProgressModel
    let onConnectGarmin: () -> Void
    var linksToRecentLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SourceStatus(model: model, onConnectGarmin: onConnectGarmin)
                if !model.hasLoaded {
                    LoadingState("Loading…")
                }
                if linksToRecentLoad {
                    RecentLoadLink(model: model, onConnectGarmin: onConnectGarmin)
                }
                if model.hasNoReadings {
                    ListEmptyState(
                        title: "No readings yet", systemImage: "heart.text.square",
                        description: Text("Connect Apple Health or Garmin to see recovery readings.")
                    )
                } else {
                    ForEach(model.readings) { reading in
                        ReadingCard(reading: reading)
                    }
                }
                if model.showsRecoveryTrends { TrendSection(model: model, charts: model.recoveryCharts) }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct ReadingCard: View {
    let reading: RecoveryReading

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text(reading.title)) {
                    Text(reading.value)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(reading.isAvailable ? .primary : .secondary)
                }
                Text(reading.summary).font(.subheadline).foregroundStyle(.secondary)
                if !reading.details.isEmpty {
                    DisclosureGroup("Source and coverage") {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            ForEach(reading.details, id: \.self) { Text($0) }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.xSmall)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

private struct RecentLoadDetail: View {
    let model: RecoveryProgressModel
    let onConnectGarmin: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SourceStatus(model: model, onConnectGarmin: onConnectGarmin)
                if !model.hasLoaded {
                    LoadingState("Loading…")
                } else if !model.showsRecentLoad {
                    ListEmptyState(
                        title: "No data yet", systemImage: "chart.bar",
                        description: Text("Log a workout to see how your recent load compares.")
                    )
                }
                if let load = model.weeklyLoad {
                    WeeklyLoadCard(load: load)
                }
                ForEach(model.loadRows) { row in
                    LoadCard(row: row)
                }
                if model.showsLoadTrends { TrendSection(model: model, charts: model.weeklyCharts) }
            }
            .padding(Spacing.medium)
        }
        .navigationTitle("Recent load")
        .navigationBarTitleDisplayModeInline()
    }
}

private struct WeeklyLoadCard: View {
    let load: WeeklyLoadReading

    private var tone: StatusTone {
        switch load.zone {
        case .below: .neutral
        case .usual: .positive
        case .above: .caution
        }
    }

    var body: some View {
        Card(tone: tone) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                SectionHeader(Text("Load")) {
                    Text(load.value).font(.title3.weight(.heavy))
                }
                RangeGauge(
                    value: load.ratio, scale: WeeklyLoadScale.scale, usual: WeeklyLoadScale.usual,
                    tone: tone, accessibilityLabel: load.status
                )
                .accessibilityHidden(true)
                Text(load.status).font(.subheadline)
                Text(load.usualRange).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LoadCard: View {
    let row: RecentLoadRow

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(row.title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(row.value).font(.title3.weight(.heavy))
                if let comparison = row.comparison {
                    Text(comparison).font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(row.details, id: \.self) {
                    Text($0).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

#Preview("Recovery & Progress") {
    NavigationStack {
        TrendsView(model: RecoveryProgressModel(sources: []))
    }
}
