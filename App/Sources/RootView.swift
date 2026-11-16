import FeatureHistory
import FeaturePlan
import FeatureSettings
import FeatureToday
import FeatureWorkout
import SwiftUI

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    @State private var todayModel: TodayModel
    @State private var workoutModel: WorkoutModel
    @State private var historyModel: HistoryModel
    @State private var planModel: PlanModel
    @State private var importModel: ImportModel
    @State private var backupModel: BackupModel
    @Environment(\.scenePhase) private var scenePhase

    init(container: AppContainer) {
        _todayModel = State(initialValue: container.makeTodayModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
        _planModel = State(initialValue: container.makePlanModel())
        _importModel = State(initialValue: container.makeImportModel())
        _backupModel = State(initialValue: container.makeBackupModel())
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
                SettingsView(importModel: importModel, backupModel: backupModel)
            }
        }
        .task { await backupModel.checkRestoreOffer() }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                Task { await backupModel.backUpIfConfigured() }
            }
        }
        .alert("Restore your data?", isPresented: $backupModel.isOfferingRestore) {
            Button("Restore") { Task { await backupModel.acceptRestoreOffer() } }
            Button("Not now", role: .cancel) { backupModel.declineRestoreOffer() }
        } message: {
            if let offer = backupModel.restoreOffer {
                Text("A backup with \(offer.sessions) sessions from "
                    + "\(offer.createdAt.formatted(date: .abbreviated, time: .shortened)) was found in your backup folder.")
            }
        }
    }
}
