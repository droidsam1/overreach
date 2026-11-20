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
import FeatureWorkout
import HistoryPresentation
import OnboardingPresentation
import PlanPresentation
import SettingsPresentation
import SwiftUI
import TodayPresentation
import WorkoutPresentation

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    private enum AppTab: Hashable {
        case today, train, history, plan, settings
    }

    @State private var todayModel: TodayModel
    @State private var workoutModel: WorkoutModel
    @State private var routinesModel: RoutinesModel
    @State private var historyModel: HistoryModel
    @State private var planModel: PlanModel
    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @State private var exercisesModel: ExercisesModel
    @State private var onboardingModel: OnboardingModel
    @State private var whatsNewModel: WhatsNewModel
    @State private var askAIModel: AskAIModel
    @State private var planImportModel: PlanImportModel
    @State private var selectedTab = AppTab.today
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @Environment(\.scenePhase) private var scenePhase
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _todayModel = State(initialValue: container.makeTodayModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _routinesModel = State(initialValue: container.makeRoutinesModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
        _planModel = State(initialValue: container.makePlanModel())
        _importModel = State(initialValue: container.makeImportModel())
        _backupModel = State(initialValue: container.makeBackupModel())
        _exercisesModel = State(initialValue: container.makeExercisesModel())
        _onboardingModel = State(initialValue: container.makeOnboardingModel())
        _whatsNewModel = State(initialValue: container.makeWhatsNewModel())
        _askAIModel = State(initialValue: container.makeAskAIModel())
        _planImportModel = State(initialValue: container.makePlanImportModel())
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "gauge.with.needle", value: AppTab.today) {
                TodayView(model: todayModel)
            }
            Tab("Train", systemImage: "dumbbell", value: AppTab.train) {
                WorkoutView(model: workoutModel, routines: routinesModel)
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView(model: historyModel)
            }
            Tab("Plan", systemImage: "list.bullet.clipboard", value: AppTab.plan) {
                PlanView(model: planModel) {
                    NavigationLink {
                        AskAIView(model: askAIModel, importer: planImportModel)
                    } label: {
                        Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(importModel: importModel, backupModel: backupModel) {
                    NavigationLink {
                        ExercisesView(model: exercisesModel)
                    } label: {
                        Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                    }
                    .badge(exercisesModel.needsMappingCount)
                    Button {
                        Task { await onboardingModel.reopen() }
                    } label: {
                        Label("Training profile", systemImage: "person.text.rectangle")
                    }
                }
            }
            .badge(exercisesModel.needsMappingCount + backupModel.badgeCount)
        }
        .preferredColorScheme(appearance.colorScheme)
        .task {
            await backupModel.load()
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
        .fullScreenCover(isPresented: $onboardingModel.isPresented) {
            OnboardingView(model: onboardingModel) { destination in
                switch destination {
                case .train:
                    selectedTab = .train
                case .importHistory:
                    selectedTab = .settings
                case .restoreBackup:
                    selectedTab = .settings
                    backupModel.requestFolderChoice()
                }
            }
        }
        .onChange(of: importModel.state) {
            // New exercises from an import need muscles: refresh the badge.
            if case .done = importModel.state {
                Task { await exercisesModel.load() }
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                Task { await backupModel.backUpIfConfigured() }
            } else if scenePhase == .active {
                // The watch's workout may have reached Health since the session was saved.
                Task { await container.reconcileHealthWorkouts() }
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
}
