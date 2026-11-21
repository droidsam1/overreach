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
                    if model.scheduledStrengthToday != nil || !model.scheduledRunsToday.isEmpty {
                        scheduledTraining
                    }
                    if let option = model.runningOption {
                        easyRun(option)
                    }
                    if let advice = model.deloadAdvice {
                        deload(advice)
                    }
                    if model.canRequestStrengthOption {
                        DisclosureGroup(
                            "I want to lift today",
                            isExpanded: Binding(
                                get: { model.showsOptionalStrength },
                                set: { model.setShowsOptionalStrength($0) }
                            )
                        ) {
                            if let option = model.strengthOption {
                                strengthDetails(option)
                            }
                        }
                    }
                    if model.showsCheckIn {
                        checkIn
                    }
                    if !model.movementNotes.isEmpty {
                        movement
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

                    if let note = model.trainingReadNote {
                        Label(note, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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

    /// A deload proposal with its reasons and the plan, or the deload week in progress.
    private func deload(_ advice: DeloadAdvice) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch advice.state {
            case let .proposed(reasons):
                Label("Deload week suggested", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(reasons, id: \.self) { reason in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(reason.text).font(.subheadline)
                        Text(reason.evidence).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(advice.planText).font(.footnote).foregroundStyle(.secondary)
                deloadApplication
                HStack {
                    Button("Start deload week") { Task { await model.acceptDeload() } }
                        .buttonStyle(.borderedProminent)
                    Button("Not now") { Task { await model.postponeDeload() } }
                        .buttonStyle(.bordered)
                }
            case let .inProgress(lastDay):
                Label("Deload week", systemImage: "arrow.down.right.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.tint)
                Text(advice.planText).font(.subheadline)
                Text("Until \(lastDay.formatted(.dateTime.weekday(.wide).day().month()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                deloadApplication
            case let .confirmBreak(period):
                Label("Did you already take a break?", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(period.text).font(.subheadline)
                Text("If it was a rest or an easier week, it counts as your deload and no new one is needed yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Yes, count it") { Task { await model.reviewBreak(accepted: true) } }
                        .buttonStyle(.borderedProminent)
                    Button("No") { Task { await model.reviewBreak(accepted: false) } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
    }

    /// How to apply the deload: the next session with fewer sets and less load, or a general example.
    @ViewBuilder private var deloadApplication: some View {
        if let howTo = model.deloadHowTo {
            Text(howTo).font(.subheadline)
        }
        if let session = model.deloadSession {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(session.heading).font(.subheadline.weight(.semibold))
                ForEach(session.rows) { row in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(row.title).font(.subheadline.weight(.medium))
                        Text(row.reference).foregroundStyle(.secondary)
                        Text(row.deload)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        nextSessionPicker
    }

    /// Lets the athlete say which workout comes next when there is no plan.
    @ViewBuilder private var nextSessionPicker: some View {
        if !model.strengthChoices.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if let note = model.strengthChoiceNote {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                Menu {
                    ForEach(model.strengthChoices) { choice in
                        Button {
                            model.chooseStrengthSession(choice.id)
                        } label: {
                            if choice.isSelected {
                                Label(choice.title, systemImage: "checkmark")
                            } else {
                                Text(choice.title)
                            }
                        }
                    }
                } label: {
                    Label("Choose your next session", systemImage: "list.bullet")
                        .font(.subheadline)
                }
            }
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
            Text(model.readinessAdvice).font(.headline).accessibilityAddTraits(.isHeader)
            StatusBadge(title: model.readinessTitle, tone: model.readinessLevel.tone)
            if let summary = model.readinessSummary {
                Text(summary).font(.subheadline)
            }
            if model.showsReadinessDetails {
                DisclosureGroup("Why this recommendation?") {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        ForEach(model.readinessLines, id: \.self) { line in
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Text(line.text).font(.subheadline)
                                    .foregroundStyle(line.kind == .unavailable ? .secondary : .primary)
                                if let source = line.source {
                                    Text(line.evidence).font(.caption).foregroundStyle(.secondary)
                                    Link("Research source", destination: source).font(.caption)
                                }
                                ReadingLinks(items: line.readings.map(ReadingLinkItem.init))
                            }
                        }
                        ForEach(model.readinessObservations, id: \.self) { observation in
                            Text(observation.text).font(.subheadline)
                                .foregroundStyle(observation.kind == .unavailable ? .secondary : .primary)
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
                        if !model.readinessSources.isEmpty {
                            readinessSourceDetails
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.small)
                }
            }
        }
    }

    private var readinessSourceDetails: some View {
        DisclosureGroup("Data sources and coverage") {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(model.readinessSources) { source in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(source.title).font(.subheadline.weight(.medium))
                        ForEach(source.details, id: \.self) { detail in
                            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.small)
        }
    }

    private func easyRun(_ option: RunningOption) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(option.goal).font(.subheadline.weight(.semibold))
            if model.scheduledRunsToday.isEmpty, let plan = option.plan {
                Text(plan).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(option.advice).font(.subheadline)
            if let context = option.context { Text(context).font(.caption).foregroundStyle(.secondary) }
            if let evidence = option.evidence, let source = option.source {
                DisclosureGroup("Why this running option?") {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text("A conversational pace keeps the effort easy. The duration is a coaching estimate.")
                        Text(evidence).foregroundStyle(.secondary)
                        Link("Research source", destination: source)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var scheduledTraining: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Today's plan").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let strength = model.scheduledStrengthToday {
                scheduledRow(strength, symbol: "dumbbell")
                if let option = model.strengthOption {
                    DisclosureGroup("Compare with an easy strength option") { strengthDetails(option) }
                }
            }
            ForEach(model.scheduledRunsToday) { run in
                scheduledRow(run, symbol: "figure.run")
            }
        }
    }

    private func scheduledRow(_ row: ScheduledTrainingRow, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Label(row.title, systemImage: symbol).font(.subheadline.weight(.semibold))
            if let status = row.status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func strengthDetails(_ option: StrengthOption) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let heading = option.heading {
                Text(heading).font(.subheadline)
            }
            if !model.showsNextSessionInDeload {
                nextSessionPicker
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

    /// Steps and walks against the usual day: context for today's training, with its evidence.
    private var movement: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("Everyday movement", systemImage: "figure.walk")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.movementNotes, id: \.self) { note in
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(note.text).font(.subheadline)
                    Text(note.evidence).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
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
    /// The display values of a curated reading (ADR-0030).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
