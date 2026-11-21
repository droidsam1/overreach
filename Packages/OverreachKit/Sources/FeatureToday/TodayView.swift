import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import TodayPresentation

/// "How should I train today?" — readiness, key recovery metrics and (phase 3) today's proposed session.
public struct TodayView: View {
    @State private var model: TodayModel
    @State private var checkInSheet: CheckInModel?
    private let onConnectGarmin: () -> Void
    private let recoveryHistory: (() -> AnyView)?
    private var recoveryDestination: (() -> AnyView)?
    private var settingsDestination: (() -> AnyView)?
    private var showsSettings = Binding.constant(false)
    private var settingsBadgeCount = 0

    public enum WorkoutContinuation {
        case resume(String), reviewDraft
    }

    private let workoutContinuation: WorkoutContinuation?
    private let onOpenTrain: () -> Void
    private let onOpenHistory: () -> Void

    public init(
        model: TodayModel, workoutContinuation: WorkoutContinuation? = nil,
        onOpenTrain: @escaping () -> Void = {}, onOpenHistory: @escaping () -> Void = {},
        onConnectGarmin: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.workoutContinuation = workoutContinuation
        self.onOpenTrain = onOpenTrain
        self.onOpenHistory = onOpenHistory
        self.onConnectGarmin = onConnectGarmin
        recoveryHistory = nil
    }

    public init<RecoveryHistory: View>(
        model: TodayModel, workoutContinuation: WorkoutContinuation? = nil,
        onOpenTrain: @escaping () -> Void = {}, onOpenHistory: @escaping () -> Void = {},
        onConnectGarmin: @escaping () -> Void = {},
        @ViewBuilder recoveryHistory: @escaping () -> RecoveryHistory
    ) {
        _model = State(initialValue: model)
        self.workoutContinuation = workoutContinuation
        self.onOpenTrain = onOpenTrain
        self.onOpenHistory = onOpenHistory
        self.onConnectGarmin = onConnectGarmin
        self.recoveryHistory = { AnyView(recoveryHistory()) }
    }

    /// Where "View recovery" goes: the readings and recent load that used to sit in Today's metrics. Pushed in
    /// Today's own stack, so going back returns to the decision.
    public func recoveryProgress<Destination: View>(
        @ViewBuilder _ destination: @escaping () -> Destination
    ) -> TodayView {
        var copy = self
        copy.recoveryDestination = { AnyView(destination()) }
        return copy
    }

    public func settingsButton<Destination: View>(
        isPresented: Binding<Bool>, badgeCount: Int, @ViewBuilder destination: @escaping () -> Destination
    ) -> TodayView {
        var copy = self
        copy.showsSettings = isPresented
        copy.settingsDestination = { AnyView(destination()) }
        copy.settingsBadgeCount = badgeCount
        return copy
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    if let workoutContinuation {
                        continueWorkout(workoutContinuation)
                    }
                    if primary == .deload, let advice = model.deloadAdvice {
                        deload(advice, prominent: true)
                    }
                    if model.showsReadinessCard {
                        readinessSummary
                    }
                    primaryButton
                    warnings
                    if model.showsReadinessDetails && model.showsReadinessCard {
                        TodayReadinessDetails(model: model)
                    }
                    if model.scheduledStrengthToday != nil || !model.scheduledRunsToday.isEmpty {
                        scheduledTraining
                    }
                    if let option = model.runningOption {
                        easyRun(option)
                    }
                    if primary != .deload, let advice = model.deloadAdvice {
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
                    if primary != .checkIn, model.showsCheckIn, model.showsReadinessCard {
                        checkIn(prominent: false)
                    }
                    if !model.movementNotes.isEmpty {
                        TodayMovement(model: model)
                    }
                    if model.showsReadinessCard {
                        if primary != .connectHealth, model.showsConnectHealth {
                            connectHealth(prominent: false)
                        }
                        if primary != .connectGarmin, model.showsConnectGarmin {
                            connectGarmin(prominent: false)
                        }
                        if let recoveryDestination {
                            NavigationLink(destination: recoveryDestination()) {
                                Label("View recovery", systemImage: "heart.text.square")
                            }
                        }
                        Button("View recent training", systemImage: "calendar", action: onOpenHistory)
                    }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Today")
            .toolbar {
                if settingsDestination != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showsSettings.wrappedValue = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .overlay(alignment: .topTrailing) {
                                    if settingsBadgeCount > 0 {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                        .accessibilityValue(Text(verbatim: settingsBadgeCount > 0 ? String(settingsBadgeCount) : ""))
                    }
                }
            }
            .navigationDestination(isPresented: showsSettings) {
                settingsDestination?()
            }
            .sheet(item: $checkInSheet) { sheet in
                CheckInView(model: sheet) { Task { await model.load() } }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    private var primary: TodayModel.NextAction {
        workoutContinuation == nil ? model.nextAction : .readiness
    }

    private func continueWorkout(_ continuation: WorkoutContinuation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            switch continuation {
            case let .resume(name):
                Button("Resume workout", systemImage: "dumbbell", action: onOpenTrain)
                Text(name).font(.subheadline)
            case .reviewDraft:
                Button("Review saved workout", systemImage: "dumbbell", action: onOpenTrain)
            }
        }
        .buttonStyle(BrandButtonStyle())
    }

    @ViewBuilder private var primaryButton: some View {
        switch primary {
        case .loading:
            ProgressView("Loading Today…")
        case .readiness, .deload:
            EmptyView()
        case .checkIn:
            checkIn(prominent: true)
        case .retry:
            retryLoad(prominent: true)
        case .connectHealth:
            connectHealth(prominent: true)
        case .connectGarmin:
            connectGarmin(prominent: true)
        case .train:
            Button("Open Train", systemImage: "dumbbell", action: onOpenTrain)
                .buttonStyle(BrandButtonStyle())
        }
    }

    @ViewBuilder private func actionButton(
        _ title: Text, symbol: String, prominent: Bool, action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) { Label { title } icon: { Image(systemName: symbol) } }
        if prominent {
            button.buttonStyle(BrandButtonStyle())
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func retryLoad(prominent: Bool) -> some View {
        actionButton(Text("Try again"), symbol: "arrow.clockwise", prominent: prominent) {
            Task { await model.load() }
        }
        .disabled(model.isLoading)
    }

    private func connectGarmin(prominent: Bool) -> some View {
        actionButton(
            Text("Connect your Garmin"), symbol: "applewatch.radiowaves.left.and.right",
            prominent: prominent, action: onConnectGarmin
        )
    }

    @ViewBuilder private var warnings: some View {
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
        if primary != .retry, model.showsSourceWarning || model.trainingReadNote != nil {
            retryLoad(prominent: false)
        }
    }

    /// A deload proposal with its reasons and the plan, or the deload week in progress.
    private func deload(_ advice: DeloadAdvice, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch advice.state {
            case let .proposed(explanation):
                DeloadProposalCard(
                    model: model, advice: advice, explanation: explanation,
                    recoveryHistory: recoveryHistory, prominent: prominent
                ) {
                    deloadApplication
                }
            case let .inProgress(lastDay, forLifeStress):
                Label(forLifeStress ? LocalizedStringKey("Steadier week") : LocalizedStringKey("Deload week"), systemImage: "arrow.down.right.circle.fill")
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
                Text(period.details.dates).font(.subheadline)
                if let strength = period.details.strength { Text(strength).font(.subheadline) }
                if let running = period.details.running { Text(running).font(.subheadline) }
                Text(period.details.reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Yes, it was rest") { Task { await model.reviewBreak(accepted: true) } }
                        .buttonStyle(.bordered)
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

    private func connectHealth(prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            actionButton(Text("Connect Apple Health"), symbol: "heart.text.square", prominent: prominent) {
                Task { await model.connectHealth() }
            }

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

    private var readinessSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(model.readinessAdvice).font(.headline).accessibilityAddTraits(.isHeader)
            StatusBadge(title: model.readinessTitle, tone: model.readinessLevel.tone)
            if let summary = model.readinessSummary {
                Text(summary).font(.subheadline)
            }
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
                        if let explanation = option.explanation { Text(explanation) }
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

    private func checkIn(prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            actionButton(
                Text(model.checkInButtonTitle), symbol: "face.smiling", prominent: prominent
            ) {
                checkInSheet = model.makeCheckInModel()
            }
            .controlSize(.large)
            if let summary = model.checkInSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
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
