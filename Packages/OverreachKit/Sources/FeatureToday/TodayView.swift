import DesignSystem
import Domain
import PresentationKit
import SwiftUI
import TodayPresentation

/// "How should I train today?" — readiness, key recovery metrics and (phase 3) today's proposed session.
public struct TodayView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: TodayModel
    @State private var savedCheckInCount = 0
    @State private var savingEnergy: Int?
    @State private var checkInSheet: CheckInModel?
    @State private var showsRun = false
    @State private var showsRunOffer = false
    @State private var showsWhy = false
    @State private var showsOptions = false
    @State private var showsForecast = false
    private var forecastModel: TodayForecastModel?
    private var forecastSettings: (() -> AnyView)?
    @State private var painPrompt: RunPainPrompt?
    private let onConnectGarmin: () -> Void
    private let recoveryHistory: (() -> AnyView)?
    private var settingsDestination: (() -> AnyView)?
    private var showsSettings = Binding.constant(false)
    private var settingsBadgeCount = 0
    private var onStartStrength: ((Routine, RotationAdjustment.Outcome?, Bool) -> Void)?
    private var onReviewRunMove: ((PlannedRun, CalendarDay) -> Void)?

    private let workoutContinuation: TodayModel.WorkoutContinuation?
    private let onOpenTrain: () -> Void
    private let onOpenHistory: () -> Void
    private let onOpenRecovery: () -> Void

    public init(
        model: TodayModel, workoutContinuation: TodayModel.WorkoutContinuation? = nil,
        onOpenTrain: @escaping () -> Void = {}, onOpenHistory: @escaping () -> Void = {},
        onOpenRecovery: @escaping () -> Void = {},
        onConnectGarmin: @escaping () -> Void = {}
    ) {
        _model = State(initialValue: model)
        self.workoutContinuation = workoutContinuation
        self.onOpenTrain = onOpenTrain
        self.onOpenHistory = onOpenHistory
        self.onOpenRecovery = onOpenRecovery
        self.onConnectGarmin = onConnectGarmin
        recoveryHistory = nil
    }

    public init<RecoveryHistory: View>(
        model: TodayModel, workoutContinuation: TodayModel.WorkoutContinuation? = nil,
        onOpenTrain: @escaping () -> Void = {}, onOpenHistory: @escaping () -> Void = {},
        onOpenRecovery: @escaping () -> Void = {},
        onConnectGarmin: @escaping () -> Void = {},
        @ViewBuilder recoveryHistory: @escaping () -> RecoveryHistory
    ) {
        _model = State(initialValue: model)
        self.workoutContinuation = workoutContinuation
        self.onOpenTrain = onOpenTrain
        self.onOpenHistory = onOpenHistory
        self.onOpenRecovery = onOpenRecovery
        self.onConnectGarmin = onConnectGarmin
        self.recoveryHistory = { AnyView(recoveryHistory()) }
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

    public func weatherForecast<Settings: View>(
        _ model: TodayForecastModel?, @ViewBuilder settings: @escaping () -> Settings
    ) -> TodayView {
        var copy = self
        copy.forecastModel = model
        copy.forecastSettings = { AnyView(settings()) }
        return copy
    }

    public func startStrength(_ action: @escaping (Routine, RotationAdjustment.Outcome?, Bool) -> Void) -> TodayView {
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
                    header
                    primaryDecision
                        .onAppear {
                            if let kind = heroFeedbackKind { model.recordRotationFeedbackShown(kind) }
                        }
                        .onChange(of: heroFeedbackKind) { _, kind in
                            if let kind { model.recordRotationFeedbackShown(kind) }
                        }
                    if let offer = rotationOffer {
                        rotationOfferLine(offer)
                            .onAppear { model.recordRotationFeedbackShown(offer.kind) }
                            .onChange(of: offer.kind) { _, kind in model.recordRotationFeedbackShown(kind) }
                    } else if let offer = model.runOffer {
                        runOfferLine(offer)
                    }
                    if model.visibleBlocks.contains(.scheduledPlan) {
                        TodayWeekCard(
                            week: model.yourWeek, strength: model.scheduledStrengthToday,
                            runs: model.scheduledRunsToday, openStrength: onOpenTrain, openRun: { showsRun = true }
                        )
                    }
                    if rotationOffer == nil, let prompt = model.pendingPrompt {
                        pendingPrompt(prompt)
                    }
                    if let prompt = model.runPainPrompt { runPainCard(prompt) }
                    ForEach(model.newSectionHints, id: \.self) { hint in
                        Text(hint).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !model.links.isEmpty { linkTiles }
                }
                .padding(Spacing.medium)
            }
            .navigationTitle("Today")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .haptic(.completed, trigger: savedCheckInCount)
            .toolbar {
                if let forecastModel {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showsForecast = true
                        } label: {
                            TodayWeatherToolbarLabel(model: forecastModel)
                        }
                        .accessibilityLabel(Text(verbatim: forecastModel.toolbarAccessibilityLabel))
                        .accessibilityValue(Text(verbatim: forecastModel.toolbarAccessibilityValue))
                    }
                }
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
            .navigationDestination(isPresented: $showsForecast) {
                if let forecastModel {
                    TodayForecastView(model: forecastModel) { forecastSettings?() }
                }
            }
            .navigationDestination(isPresented: $showsWhy) { whyScreen }
            .navigationDestination(isPresented: $showsOptions) { optionsScreen }
            .navigationDestination(isPresented: $showsRunOffer) {
                if let offer = model.runOffer { runOfferDetails(offer) }
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
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
            .sheet(item: $painPrompt) { prompt in RunPainSheet(model: model, prompt: prompt) }
            .sheet(item: $checkInSheet) { sheet in
                CheckInView(model: sheet) {
                    savedCheckInCount += 1
                    model.recordWarmUpQuestionSaved(sheet)
                    Task { await model.load() }
                }
            }
            .onChange(of: model.sectionHintCandidates) { model.updateSectionHints() }
            .task { await reload() }
            .task { await forecastModel?.load() }
            .refreshable { await reload() }
        }
    }

    /// The large date above the hero; "Today" is the navigation title.
    private var header: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func reload() async {
        await model.load()
        model.updateSectionHints()
    }

    private var linkTiles: some View {
        let links = model.links
        let columns = typeSize.isAccessibilitySize ? 2 : links.count
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.small), count: columns),
            spacing: Spacing.small
        ) {
            ForEach(links, id: \.self) { link in
                switch link {
                case .why:
                    Button { showsWhy = true } label: {
                        LinkTile(title: "Why", symbolName: "questionmark.circle", color: .orange)
                    }
                case .otherOptions:
                    Button { showsOptions = true } label: {
                        LinkTile(title: "Options", symbolName: "arrow.triangle.branch", color: .blue)
                    }
                case .recovery:
                    Button(action: onOpenRecovery) {
                        LinkTile(title: "Recovery", symbolName: "heart.text.square", color: .teal)
                    }
                case .history:
                    Button(action: onOpenHistory) {
                        LinkTile(title: "History", symbolName: "clock.fill", color: .purple)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Level 2: everything that explains the decision. The cards of running advice, deload and movement keep
    /// their place below the reasons.
    private var whyScreen: some View {
        TodayWhyView(model: model) {
            if let option = model.runningOption, !option.isOptional { easyRun(option).whyExtraCard() }
            if primary != .deload, let advice = model.deloadAdvice, !advice.isBreakConfirmation {
                deload(advice)
            }
            if !model.movementNotes.isEmpty { TodayMovement(model: model) }
            if let note = model.trainingReadNote {
                Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
            }
        }
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
                        if let option = model.strengthOption {
                            strengthDetails(option, runAdvice: model.optionalStrengthRunAdvice)
                        }
                    }
                }
                if model.showsScheduledStrengthExample, let option = model.strengthOption {
                    DisclosureGroup("Compare with an easy strength option") { strengthDetails(option) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle("Other options")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The one secondary prompt under the hero (ADR-0041).
    @ViewBuilder private func pendingPrompt(_ prompt: TodayPrompt) -> some View {
        switch prompt {
        case .sourceFailure:
            TodayPromptCard(title: Text("Source update failed"), dismiss: model.dismissPendingPrompt) {
                sourceFailurePrompt
            }
        case .confirmBreak:
            if case let .confirmBreak(period)? = model.deloadAdvice?.state { breakPrompt(period) }
        case .dogRun:
            if let question = model.dogRunQuestion {
                DogCompanionQuestionCard(
                    title: question.text, detail: question.detail, dismiss: model.dismissPendingPrompt
                ) {
                    model.answerDogRun(question, withDog: $0)
                }
            }
        case .checkIn:
            quickCheckInPrompt
        case .connectHealth:
            TodayPromptCard(
                title: Text("Apple Health"), detail: Text("Use health data to inform your training recommendation."),
                dismiss: model.dismissPendingPrompt
            ) {
                connectHealth(prominent: false)
            }
        case .connectGarmin:
            TodayPromptCard(
                title: Text("Garmin"), detail: Text("Use health data to inform your training recommendation."),
                dismiss: model.dismissPendingPrompt
            ) {
                connectGarmin(prominent: false)
            }
        case .dogWalk:
            if let question = model.dogWalkQuestion {
                DogCompanionQuestionCard(
                    title: question.text, detail: question.detail, dismiss: model.dismissPendingPrompt
                ) {
                    model.answerDogWalk(withDog: $0)
                }
            }
        case .profileQuestion:
            if let card = model.profileQuestion {
                ProfileQuestionPrompt(
                    card: card, answer: { answer in Task { await model.answerProfileQuestion(answer) } },
                    later: model.postponeProfileQuestion
                )
            }
        }
    }

    private var quickCheckInPrompt: some View {
        TodayPromptCard(
            title: Text(model.checkInButtonTitle),
            detail: Text("Your answer can change today's recommendation."),
            dismiss: model.dismissPendingPrompt
        ) {
            AnswerScale(
                options: model.quickCheckIn.map {
                    AnswerOption(id: String($0.value), symbolName: energySymbol($0.value), label: $0.name)
                },
                selectedID: (savingEnergy ?? model.checkIn?.energy).map { String($0) },
                playsSelectionFeedback: false
            ) { id in
                guard savingEnergy == nil, let answer = Int(id) else { return }
                savingEnergy = answer
                Task {
                    if await model.answerQuickCheckIn(answer) { savedCheckInCount += 1 }
                    if model.quickCheckInNeedsDetails || model.checkIn?.energy != answer {
                        let sheet = model.makeCheckInModel()
                        sheet?.energy = answer
                        checkInSheet = sheet
                    }
                    savingEnergy = nil
                }
            }
            if let summary = model.checkInSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            Button(model.quickCheckInMoreTitle) { checkInSheet = model.makeCheckInModel() }
                .controlSize(.large)
        }
        .disabled(savingEnergy != nil)
    }

    private func energySymbol(_ energy: Int) -> String {
        switch energy {
        case 1: "cloud.bolt"
        case 2: "cloud.rain"
        case 3: "minus.circle"
        case 4: "sun.min"
        default: "sun.max"
        }
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
        TodayPromptCard(
            title: Text("Did you already take a break?"), detail: Text(period.details.reason),
            dismiss: model.dismissPendingPrompt
        ) {
            Text(period.details.dates).font(.subheadline)
            if let strength = period.details.strength { Text(strength).font(.subheadline) }
            if let running = period.details.running { Text(running).font(.subheadline) }
            ViewThatFits(in: .horizontal) {
                HStack { breakAnswers }
                VStack(alignment: .leading, spacing: Spacing.small) { breakAnswers }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder private var breakAnswers: some View {
        Button("Yes, it was rest") { Task { await model.reviewBreak(accepted: true) } }
        Button("No") { Task { await model.reviewBreak(accepted: false) } }
    }

    private var primary: TodayModel.NextAction {
        model.nextAction(continuing: workoutContinuation)
    }

    private var heroFeedbackKind: RotationFeedback.Kind? {
        workoutContinuation == nil ? model.heroRotationFeedbackKind : nil
    }

    @ViewBuilder private var primaryDecision: some View {
        if let title = model.primaryActionTitle(continuing: workoutContinuation), model.doneToday != nil {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                TodayHero(model: model, openWhy: { showsWhy = true }, action: { EmptyView() })
                primaryAction(title).frame(maxWidth: .infinity)
            }
        } else if let title = model.primaryActionTitle(continuing: workoutContinuation) {
            TodayHero(
                model: model, openWhy: { showsWhy = true },
                action: {
                    primaryAction(title)
                    if case let .resume(name) = workoutContinuation {
                        Text(name).font(.subheadline)
                    }
                }
            )
        } else {
            TodayHeroPlaceholder()
        }
    }

    @ViewBuilder private func primaryAction(_ title: String) -> some View {
        switch primary {
        case .continueWorkout, .train:
            actionButton(Text(title), symbol: "dumbbell", prominent: true, action: onOpenTrain)
        case .loading:
            LoadingState("Loading Today…")
        case let .startStrength(routine):
            actionButton(Text(title), symbol: "dumbbell", prominent: true) {
                startRecommendedStrength(routine)
            }
        case .runEasy, .reviewRun:
            actionButton(Text(title), symbol: "figure.run", prominent: true) { showsRun = true }
        case .rest:
            actionButton(Text(title), symbol: "heart.text.square", prominent: true) {
                Task { await model.logRest() }
            }
        case .restLogged:
            actionButton(Text(title), symbol: "arrow.uturn.backward", prominent: false) {
                Task { await model.undoRest() }
            }
        case .trainedToday:
            actionButton(Text(title), symbol: "plus", prominent: false, action: onOpenTrain)
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
            model.recordRotationCapStarted()
            onStartStrength(routine, model.rotationCap(for: routine), model.startsFromRotationHistory(routine))
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
            button.buttonStyle(ToneButtonStyle(tone: model.readinessLevel.tone))
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

    /// A deload proposal with its reasons and the plan, or the deload week in progress.
    @ViewBuilder private func deload(_ advice: DeloadAdvice, primaryTitle: String? = nil) -> some View {
        if let primaryTitle {
            deloadContent(advice, primaryTitle: primaryTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Card(radius: Radius.tile) { deloadContent(advice, primaryTitle: nil) }
        }
    }

    private func deloadContent(_ advice: DeloadAdvice, primaryTitle: String?) -> some View {
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
                ViewThatFits(in: .horizontal) {
                    HStack { breakAnswers }
                    VStack(alignment: .leading, spacing: Spacing.small) { breakAnswers }
                }
                .buttonStyle(.bordered)
            }
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

    private func runPainCard(_ prompt: RunPainPrompt) -> some View {
        Button { painPrompt = prompt } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(prompt.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(prompt.summary).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
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
                // Side by side, stacked when the titles no longer fit (accessibility text sizes).
                ViewThatFits(in: .horizontal) {
                    HStack { runAdjustmentAnswers(adjustment) }
                    VStack(alignment: .leading, spacing: Spacing.small) { runAdjustmentAnswers(adjustment) }
                }
                .buttonStyle(.bordered)
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

    private var rotationOffer: TodayRotationOffer? {
        workoutContinuation == nil ? model.rotationOffer : nil
    }

    private func rotationOfferLine(_ offer: TodayRotationOffer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(offer.title).font(.subheadline)
            Text(offer.orderPreview).font(.footnote).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.medium) { rotationOfferActions(offer) }
                VStack(alignment: .leading, spacing: Spacing.small) { rotationOfferActions(offer) }
            }
            if let error = model.rotationSaveError {
                Text(error).font(.footnote).foregroundStyle(StatusTone.critical.accent)
            }
        }
    }

    @ViewBuilder private func rotationOfferActions(_ offer: TodayRotationOffer) -> some View {
        Button(offer.acceptTitle) {
            Task {
                if let routine = await model.acceptRotation() { startRecommendedStrength(routine) }
            }
        }
        .disabled(model.isAcceptingRotation)
        Button(offer.dismissTitle) { model.dismissRotation() }
            .disabled(model.isAcceptingRotation)
    }

    /// One secondary line under the rest hero, not a block of its own (ADR-0041).
    private func runOfferLine(_ offer: RunOffer) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.small) { runOfferContent(offer) }
            VStack(alignment: .leading, spacing: Spacing.small) { runOfferContent(offer) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func runOfferContent(_ offer: RunOffer) -> some View {
        Button { showsRunOffer = true } label: {
            Label(offer.summary, systemImage: "figure.run")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel(offer.accessibilityLabel)
        .accessibilityHint(Text("Opens the details"))
        Button(offer.dismissTitle) { model.dismissRunOffer() }
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }

    private func runOfferDetails(_ offer: RunOffer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                Text(offer.title).font(.headline)
                if let plan = offer.plan { Text(plan).font(.subheadline) }
                Text(offer.reason).font(.subheadline)
                if let explanation = offer.explanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary)
                }
                if let fallback = offer.fallback { Text(fallback).font(.subheadline) }
                Button(offer.dismissTitle) {
                    model.dismissRunOffer()
                    showsRunOffer = false
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
        }
        .navigationTitle("Run details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private func runAdjustmentAnswers(_ adjustment: RunningOption.Adjustment) -> some View {
        Button(adjustment.applyTitle) { Task { await model.applyRunningAdjustment() } }
        Button(adjustment.keepTitle) { model.keepPlannedRun() }
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

    private func strengthDetails(_ option: StrengthOption, runAdvice: [String] = []) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            if let heading = option.heading {
                Text(heading).font(.subheadline)
            }
            if !model.showsNextSessionInDeload {
                nextSessionPicker
            }
            if runAdvice.isEmpty {
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
            } else {
                ForEach(runAdvice, id: \.self) { line in
                    Text(line).font(.subheadline)
                }
            }
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

#if DEBUG
/// Sample data for previews.
struct PreviewMetricsSource: MetricsSource {
    let kind: DataSourceKind = .garmin
    /// HRV of the last nights; the earlier ones are 43 ms. Below the baseline gives an amber day.
    var recentHRV = 34.0
    /// Never answers, to preview the loading state.
    var neverAnswers = false

    func isAvailable() async -> Bool { true }

    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        if neverAnswers { try await Task.sleep(for: .seconds(3_600)) }
        let calendar = Calendar.current
        return (0...25).map { offset in
            let day = range.upperBound.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.hrvRMSSDMs = offset < 4 ? recentHRV : 43
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

#Preview("Amber") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource()]))
}

#Preview("Green") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource(recentHRV: 43)]))
}

#Preview("Unknown") {
    TodayView(model: TodayModel(sources: []))
}

#Preview("Loading") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource(neverAnswers: true)]))
}

#Preview("Amber · Dark") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource()]))
        .preferredColorScheme(.dark)
}

#Preview("Green · Largest text in dark mode") {
    TodayView(model: TodayModel(sources: [PreviewMetricsSource(recentHRV: 43)]))
        .environment(\.dynamicTypeSize, .accessibility5)
        .preferredColorScheme(.dark)
}
#endif

extension ReadingLinkItem {
    /// The display values of a curated reading (ADR-0030).
    init(_ reading: Reading) {
        self.init(url: reading.url, title: reading.title, detail: reading.detail(), note: reading.note)
    }
}
