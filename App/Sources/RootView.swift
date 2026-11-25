import AssistantPresentation
import DesignSystem
import ExercisesPresentation
import FeatureAssistant
import FeatureExercises
import FeatureHistory
import FeatureOnboarding
import FeaturePlan
import FeatureSettings
import FeatureToday
import FeatureTrends
import FeatureWorkout
import HistoryPresentation
import OnboardingPresentation
import PlanPresentation
import SettingsPresentation
import SwiftUI
import TodayPresentation
import TrendsPresentation
import WorkoutPresentation

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    private enum AppTab: Hashable {
        case today, train, history, plan, recovery
    }

    @State private var todayModel: TodayModel
    @State private var recoveryModel: RecoveryProgressModel
    @State private var workoutModel: WorkoutModel
    @State private var routinesModel: RoutinesModel
    @State private var historyModel: HistoryModel
    @State private var planModel: PlanModel
    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @State private var trainingSettingsModel: TrainingSettingsModel
    @State private var garminModel: GarminSetupModel
    @State private var exercisesModel: ExercisesModel
    @State private var onboardingModel: OnboardingModel
    @State private var whatsNewModel: WhatsNewModel
    @State private var askAIModel: AskAIModel
    @State private var planImportModel: PlanImportModel
    @State private var suggestedRun: RunningCalendarDraft?
    @State private var selectedTab: AppTab
    @State private var onboardingDestination: OnboardingDestination?
    @State private var showsStrongImport = false
    @State private var showsSettings = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @Environment(\.scenePhase) private var scenePhase
    private let container: AppContainer

    private var garminSetupInSetup: Binding<Bool> {
        Binding(
            get: { garminModel.isPresented && onboardingModel.isPresented },
            set: { if !$0 { garminModel.finish() } }
        )
    }

    private var garminSetupInApp: Binding<Bool> {
        Binding(
            get: { garminModel.isPresented && !onboardingModel.isPresented },
            set: { if !$0 { garminModel.finish() } }
        )
    }

    init(container: AppContainer) {
        self.container = container
        _todayModel = State(initialValue: container.makeTodayModel())
        _recoveryModel = State(initialValue: container.makeRecoveryProgressModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _selectedTab = State(initialValue: .today)
        _routinesModel = State(initialValue: container.makeRoutinesModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
        _planModel = State(initialValue: container.makePlanModel())
        _importModel = State(initialValue: container.makeImportModel())
        _backupModel = State(initialValue: container.makeBackupModel())
        _trainingSettingsModel = State(initialValue: container.makeTrainingSettingsModel())
        _garminModel = State(initialValue: container.makeGarminSetupModel())
        _exercisesModel = State(initialValue: container.makeExercisesModel())
        _onboardingModel = State(initialValue: container.makeOnboardingModel())
        _whatsNewModel = State(initialValue: container.makeWhatsNewModel())
        _askAIModel = State(initialValue: container.makeAskAIModel())
        _planImportModel = State(initialValue: container.makePlanImportModel())
    }

    private var workoutContinuation: TodayModel.WorkoutContinuation? {
        if workoutModel.isSessionActive { return .resume(workoutModel.sessionName) }
        if let name = workoutModel.recoverableWorkoutName { return .resume(name) }
        if workoutModel.needsDraftRecovery { return .reviewDraft }
        return nil
    }

    private func openWorkout() {
        selectedTab = .train
        if workoutModel.canResumeWorkout {
            Task { await workoutModel.resumeSavedWorkout() }
        }
    }

    /// Recovery & Progress, with the progress detail from Plan's analysis. `section` opens one detail directly.
    private func recoveryProgress(section: RecoveryProgressModel.Section?) -> some View {
        TrendsView(
            model: recoveryModel, section: section, progressSummary: planModel.progressSummary,
            onConnectGarmin: { garminModel.start() },
            progress: { PlanProgressView(model: planModel) }
        )
        .navigationDestination(for: PerformanceSession.self) { session in
            performanceSession(session)
                .task { await historyModel.load() }
                .onDisappear { Task { await recoveryModel.load() } }
        }
    }

    @ViewBuilder private func performanceSession(_ session: PerformanceSession) -> some View {
        switch session {
        case let .run(run):
            HistoryRunDetail(run: historyModel.runDetail(for: run), history: historyModel)
        case let .strength(sessionID, setID):
            if historyModel.isLoading && historyModel.session(id: sessionID) == nil {
                ProgressView("Loading…")
            } else {
                SessionDetailView(model: historyModel, sessionID: sessionID, highlightedSetID: setID)
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "gauge.with.needle", value: AppTab.today) {
                TodayView(
                    model: todayModel, workoutContinuation: workoutContinuation,
                    onOpenTrain: openWorkout, onOpenHistory: { selectedTab = .history },
                    onOpenRecovery: { selectedTab = .recovery },
                    onConnectGarmin: { garminModel.start() },
                    recoveryHistory: { PlanProgressView(model: planModel) }
                )
                .startStrength { routine, rotationCap, startsFromRotationHistory in
                    selectedTab = .train
                    Task {
                        await workoutModel.start(
                            routine, startsFromRotationHistory: startsFromRotationHistory, rotationCap: rotationCap
                        )
                    }
                }
                .reviewRunMove { entry, day in
                    suggestedRun = planModel.reviewRunMove(entry, to: day)
                    selectedTab = .plan
                }
                .settingsButton(
                    isPresented: $showsSettings,
                    badgeCount: exercisesModel.needsMappingCount + backupModel.badgeCount + garminModel.badgeCount
                ) {
                    settings
                }
            }
            Tab("Train", systemImage: "dumbbell", value: AppTab.train) {
                WorkoutView(model: workoutModel, routines: routinesModel)
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView(model: historyModel, onOpenTrain: openWorkout)
            }
            Tab("Plan", systemImage: "list.bullet.clipboard", value: AppTab.plan) {
                PlanView(model: planModel, suggestedRun: $suggestedRun, assistant: {
                    NavigationLink {
                        AskAIView(model: askAIModel, importer: planImportModel)
                    } label: {
                        Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
                    }
                }, progress: {
                    recoveryProgress(section: .progress)
                })
            }
            Tab("Recovery", systemImage: "heart.text.square", value: AppTab.recovery) {
                NavigationStack {
                    recoveryProgress(section: nil)
                        .task { await planModel.load() }
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            await backupModel.load()
            await garminModel.load()
            await backupModel.checkRestoreOffer()
            await exercisesModel.load()
            // With a backup on offer, the setup waits for the answer: a restore makes it unnecessary.
            if !backupModel.isOfferingRestore {
                await onboardingModel.presentIfNeeded()
            }
            // The first-run tour covers this version; anyone else sees what changed since their last version.
            if onboardingModel.isPresented {
                await whatsNewModel.markCurrentAsSeen()
            } else if !backupModel.isOfferingRestore {
                await whatsNewModel.checkAtLaunch()
            }
        }
        .sheet(isPresented: $whatsNewModel.isPresented, onDismiss: {
            Task { await whatsNewModel.markCurrentAsSeen() }
        }) {
            WhatsNewView(model: whatsNewModel)
        }
        .fullScreenCover(isPresented: $onboardingModel.isPresented, onDismiss: openOnboardingDestination) {
            OnboardingView(
                model: onboardingModel,
                isGarminConnected: garminModel.isConnected,
                onConnectHealth: { Task { await todayModel.connectHealth() } },
                onConnectGarmin: { garminModel.start() }
            ) { destination in
                onboardingDestination = destination
            }
            // The Garmin setup over the first-run setup (the devices step opens it).
            .sheet(isPresented: garminSetupInSetup) { GarminSetupView(model: garminModel) }
        }
        // The Garmin setup from Settings or Today. One model, shown over whatever is on screen.
        .sheet(isPresented: garminSetupInApp) { GarminSetupView(model: garminModel) }
        .onChange(of: garminModel.connection?.lastSync) {
            if recoveryModel.hasLoaded { Task { await recoveryModel.load() } }
        }
        .onChange(of: garminModel.isConnected) {
            // New Garmin data: Today shows it at once.
            Task { await todayModel.load() }
            Task { await recoveryModel.load() }
        }
        .onChange(of: planModel.profile.goal) {
            Task { await todayModel.load() }
        }
        .onChange(of: trainingSettingsModel.weightUnit) {
            Task { await todayModel.load() }
            Task { await recoveryModel.load() }
        }
        .onChange(of: importModel.state) {
            // New exercises from an import need muscles: refresh the badge.
            if case .done = importModel.state {
                Task { await exercisesModel.load() }
                Task { await recoveryModel.load() }
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                workoutModel.retryDraftAccess()
                Task { await backupModel.backUpIfConfigured() }
            } else if scenePhase == .active {
                // The watch's workout may have reached Health since the session was saved.
                Task {
                    await container.reconcileHealthWorkouts()
                    if recoveryModel.hasLoaded { await recoveryModel.load() }
                }
            }
        }
        .alert("Restore your data?", isPresented: $backupModel.isOfferingRestore) {
            Button("Restore") {
                Task {
                    await backupModel.acceptRestoreOffer()
                    await onboardingModel.presentIfNeeded()
                }
            }
            Button("Not now", role: .cancel) {
                backupModel.declineRestoreOffer()
                Task { await onboardingModel.presentIfNeeded() }
            }
        } message: {
            if let message = backupModel.restoreOfferMessage {
                Text(message)
            }
        }
    }

    private var settings: some View {
        SettingsView(
            importModel: importModel, backupModel: backupModel, garminModel: garminModel,
            trainingModel: trainingSettingsModel, showsStrongImport: $showsStrongImport
        ) {
            NavigationLink {
                ExercisesView(model: exercisesModel)
            } label: {
                Label("Exercises", systemImage: "figure.strengthtraining.traditional")
            }
            .badge(exercisesModel.needsMappingCount)
            NavigationLink {
                TrainingProfileView(model: container.makeTrainingProfileModel()) {
                    Task { await todayModel.load() }
                }
            } label: {
                Label("Training profile", systemImage: "person.text.rectangle")
            }
        }
    }

    private func openOnboardingDestination() {
        guard let destination = onboardingDestination else { return }
        onboardingDestination = nil
        switch destination {
        case .train:
            selectedTab = .train
        case .importHistory:
            selectedTab = .today
            showsSettings = true
            showsStrongImport = true
        case .restoreBackup:
            selectedTab = .today
            showsSettings = true
            backupModel.requestFolderChoice()
        }
    }
}
