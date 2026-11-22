import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import TodayPresentation

/// "How should I train today?" — readiness, key recovery metrics and (phase 3) today's proposed session.
public struct TodayView: View {
    @State private var model: TodayModel
    @State private var checkInSheet: CheckInModel?
    @State private var showsRun = false
    @State private var showsRestRecovery = false
    @State private var showsWhy = false
    @State private var showsOptions = false
    private let onConnectGarmin: () -> Void
    private let recoveryHistory: (() -> AnyView)?
    private var recoveryDestination: (() -> AnyView)?
    private var settingsDestination: (() -> AnyView)?
    private var showsSettings = Binding.constant(false)
    private var settingsBadgeCount = 0
    private var onStartStrength: ((Routine) -> Void)?
    private var onReviewRunMove: ((PlannedRun, CalendarDay) -> Void)?

    private let workoutContinuation: TodayModel.WorkoutContinuation?
    private let onOpenTrain: () -> Void
    private let onOpenHistory: () -> Void

    public init(
        model: TodayModel, workoutContinuation: TodayModel.WorkoutContinuation? = nil,
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
        model: TodayModel, workoutContinuation: TodayModel.WorkoutContinuation? = nil,
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

    public func startStrength(_ action: @escaping (Routine) -> Void) -> TodayView {
        var copy = self
        copy.onStartStrength = action
        return copy
    }

    public func reviewRunMove(_ action: @escaping (PlannedRun, CalendarDay) -> Void) -> TodayView {
        var copy = self
        copy.onReviewRunMove = action
        return copy
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    primaryDecision
                    if model.scheduledStrengthToday != nil || !model.scheduledRunsToday.isEmpty {
                        scheduledTraining
                    }
                    if let prompt = model.pendingPrompt {
                        pendingPrompt(prompt)
                    }
                    linkRow
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Today")
            .toolbar {
                if settingsDestination != nil {
                    ToolbarItem(placement: .primaryAction) {
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
            .navigationDestination(isPresented: $showsWhy) { whyScreen }
            .navigationDestination(isPresented: $showsOptions) { optionsScreen }
            .navigationDestination(isPresented: $showsRestRecovery) {
                if let recoveryDestination {
                    recoveryDestination()
                } else {
                    ScrollView { TodayReadinessDetails(model: model).padding(Spacing.medium) }
                }
            }
            .navigationDestination(isPresented: $showsRun) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        ForEach(model.scheduledRunsToday) { run in
                            scheduledRow(run, symbol: "figure.run")
                        }
                        if let option = model.runningOption { easyRun(option) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.medium)
                }
                .navigationTitle("Run details")
            }
            .sheet(item: $checkInSheet) { sheet in
                CheckInView(model: sheet) { Task { await model.load() } }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    /// Level 1 ends here: one row of routes to the pushed screens (ADR-0041).
    @ViewBuilder private var linkRow: some View {
        if !model.links.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.medium) { linkButtons }
                VStack(alignment: .leading, spacing: Spacing.small) { linkButtons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var linkButtons: some View {
        ForEach(model.links, id: \.self) { link in
            switch link {
            case .why:
                Button("Why", systemImage: "questionmark.circle") { showsWhy = true }
            case .otherOptions:
                Button("Other options", systemImage: "arrow.triangle.branch") { showsOptions = true }
            case .recovery:
                if let recoveryDestination {
                    NavigationLink(destination: recoveryDestination()) {
                        Label("Recovery", systemImage: "heart.text.square")
                    }
                } else {
                    Button("Recovery", systemImage: "heart.text.square") { showsRestRecovery = true }
                }
            case .history:
                Button("History", systemImage: "calendar", action: onOpenHistory)
            }
        }
    }

    /// Level 2: everything that explains the decision.
    private var whyScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if model.showsReadinessDetails { TodayReadinessDetails(model: model, startsExpanded: true) }
                if let option = model.runningOption, !option.isOptional { easyRun(option) }
                if primary != .deload, let advice = model.deloadAdvice, !advice.isBreakConfirmation {
                    deload(advice)
                }
                if !model.movementNotes.isEmpty { TodayMovement(model: model) }
                if let note = model.trainingReadNote {
                    Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle("Why this recommendation?")
    }

    /// Level 2: alternatives to the hero.
    private var optionsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if let option = model.runningOption, option.isOptional {
                    DisclosureGroup("I want to run today") { easyRun(option) }
                }
                if model.canRequestStrengthOption {
                    DisclosureGroup(
                        "I want to lift today",
                        isExpanded: Binding(
                            get: { model.showsOptionalStrength },
                            set: { model.setShowsOptionalStrength($0) }
                        )
                    ) {
                        if let option = model.strengthOption { strengthDetails(option) }
                    }
                }
                if model.scheduledStrengthToday != nil, let option = model.strengthOption {
                    DisclosureGroup("Compare with an easy strength option") { strengthDetails(option) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle("Other options")
    }

    /// The one secondary prompt under the hero (ADR-0041).
    @ViewBuilder private func pendingPrompt(_ prompt: TodayPrompt) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch prompt {
            case .sourceFailure: sourceFailurePrompt
            case .confirmBreak:
                if case let .confirmBreak(period)? = model.deloadAdvice?.state { breakPrompt(period) }
            case .checkIn: checkIn(prominent: false)
            case .connectHealth: connectHealth(prominent: false)
            case .connectGarmin: connectGarmin(prominent: false)
            case .dogWalk:
                if let question = model.dogWalkQuestion {
                    DogWalkQuestionCard(question: question) { model.answerDogWalk(withDog: $0) }
                }
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
    }

    @ViewBuilder private var sourceFailurePrompt: some View {
        if let note = model.trainingReadNote {
            Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
        }
        if model.showsSourceWarning {
            Label("Some sources could not be updated.", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.secondary)
            if let detail = model.sourceWarningDetail {
                Text(detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        retryLoad(prominent: false)
    }

    private func breakPrompt(_ period: DeloadAdvice.DetectedBreak) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Label("Did you already take a break?", systemImage: "questionmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(period.details.dates).font(.subheadline)
            if let strength = period.details.strength { Text(strength).font(.subheadline) }
            if let running = period.details.running { Text(running).font(.subheadline) }
            Text(period.details.reason).font(.footnote).foregroundStyle(.secondary)
            HStack {
                Button("Yes, it was rest") { Task { await model.reviewBreak(accepted: true) } }
                    .buttonStyle(.bordered)
                Button("No") { Task { await model.reviewBreak(accepted: false) } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var primary: TodayModel.NextAction {
        model.nextAction(continuing: workoutContinuation)
    }

    @ViewBuilder private var primaryDecision: some View {
        if let title = model.primaryActionTitle(continuing: workoutContinuation) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                if model.showsReadinessCard { readinessSummary }
                primaryAction(title)
                if case let .resume(name) = workoutContinuation {
                    Text(name).font(.subheadline)
                }
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
        } else {
            ProgressView("Loading Today…")
        }
    }

    @ViewBuilder private func primaryAction(_ title: String) -> some View {
        switch primary {
        case .continueWorkout, .train:
            actionButton(Text(title), symbol: "dumbbell", prominent: true, action: onOpenTrain)
        case .loading:
            ProgressView("Loading Today…")
        case let .startStrength(routine):
            actionButton(Text(title), symbol: "dumbbell", prominent: true) {
                startRecommendedStrength(routine)
            }
        case .runEasy, .reviewRun:
            actionButton(Text(title), symbol: "figure.run", prominent: true) { showsRun = true }
        case .rest:
            actionButton(Text(title), symbol: "heart.text.square", prominent: true) { showsRestRecovery = true }
        case .deload:
            primaryDeload(title: title)
        case .checkIn:
            checkIn(prominent: true, title: title)
        case .retry:
            actionButton(Text(title), symbol: "arrow.clockwise", prominent: true) {
                Task { await model.load() }
            }
            .disabled(model.isLoading)
        case .connectHealth:
            connectHealth(prominent: true, title: Text(title))
        case .connectGarmin:
            actionButton(
                Text(title), symbol: "applewatch.radiowaves.left.and.right", prominent: true, action: onConnectGarmin
            )
        }
    }

    private func startRecommendedStrength(_ routine: Routine) {
        if let onStartStrength {
            onStartStrength(routine)
        } else {
            onOpenTrain()
        }
    }

    @ViewBuilder private func primaryDeload(title: String) -> some View {
        if let advice = model.deloadAdvice {
            deload(advice, primaryTitle: title)
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
    private func deload(_ advice: DeloadAdvice, primaryTitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            switch advice.state {
            case let .proposed(explanation):
                DeloadProposalCard(
                    model: model, advice: advice, explanation: explanation,
                    recoveryHistory: recoveryHistory, primaryTitle: primaryTitle
                ) {
                    deloadApplication
                }
            case let .inProgress(lastDay, forLifeStress):
                Label(
                    DeloadProposalText.weekInProgress(steadier: forLifeStress),
                    systemImage: "arrow.down.right.circle.fill"
                )
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
        .padding(primaryTitle == nil ? Spacing.medium : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if primaryTitle == nil { RoundedRectangle(cornerRadius: Radius.card).fill(.background.secondary) }
        }
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

    private func connectHealth(
        prominent: Bool, title: Text = Text("Connect Apple Health")
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            actionButton(title, symbol: "heart.text.square", prominent: prominent) {
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
            Text(model.heroTitle).font(.headline).accessibilityAddTraits(.isHeader)
            StatusBadge(title: model.readinessTitle, tone: model.readinessLevel.tone)
            Text(model.heroReason).font(.subheadline)
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
            if let adjustment = option.adjustment {
                HStack {
                    Button(adjustment.applyTitle) { Task { await model.applyRunningAdjustment() } }
                        .buttonStyle(.bordered)
                    Button(adjustment.keepTitle) { model.keepPlannedRun() }
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, Spacing.xSmall)
                if let day = adjustment.moveDay, let title = adjustment.moveTitle, let onReviewRunMove {
                    Button(title) { onReviewRunMove(adjustment.original, day) }
                }
            }
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

    private func checkIn(prominent: Bool, title: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            actionButton(
                Text(title ?? model.checkInButtonTitle), symbol: "face.smiling", prominent: prominent
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

#Preview("Today hero · Large text in dark mode") {
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
