import ExercisesPresentation
import FeatureExercises
import FeatureHistory
import FeaturePlan
import FeatureSettings
import FeatureToday
import FeatureWorkout
import HistoryPresentation
import PlanPresentation
import SettingsPresentation
import SwiftUI
import TodayPresentation
import WorkoutPresentation

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    @State private var todayModel: TodayModel
    @State private var workoutModel: WorkoutModel
    @State private var historyModel: HistoryModel
    @State private var planModel: PlanModel
    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @State private var exercisesModel: ExercisesModel
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer) {
        _todayModel = State(initialValue: container.makeTodayModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
        _planModel = State(initialValue: container.makePlanModel())
        _importModel = State(initialValue: container.makeImportModel())
        _backupModel = State(initialValue: container.makeBackupModel())
        _exercisesModel = State(initialValue: container.makeExercisesModel())
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "gauge.with.needle") {
                TodayView(model: todayModel)
            }
            Tab("Train", systemImage: "dumbbell") {
                WorkoutView(model: workoutModel)
            }
            Tab("History", systemImage: "calendar") {
                HistoryView(model: historyModel)
            }
            Tab("Plan", systemImage: "list.bullet.clipboard") {
                PlanView(model: planModel)
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView(importModel: importModel, backupModel: backupModel) {
                    NavigationLink {
                        ExercisesView(model: exercisesModel)
                    } label: {
                        Label("Exercises", systemImage: "figure.strengthtraining.traditional")
                    }
                    .badge(exercisesModel.needsMappingCount)
                }
            }
            .badge(exercisesModel.needsMappingCount)
        }
        .task {
            await backupModel.checkRestoreOffer()
            await exercisesModel.load()
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
            }
        }
        .alert("Restore your data?", isPresented: $backupModel.isOfferingRestore) {
            Button("Restore") { Task { await backupModel.acceptRestoreOffer() } }
            Button("Not now", role: .cancel) { backupModel.declineRestoreOffer() }
        } message: {
            if let message = backupModel.restoreOfferMessage {
                Text(message)
            }
        }
    }
}
