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

    init(container: AppContainer) {
        _todayModel = State(initialValue: container.makeTodayModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
        _planModel = State(initialValue: container.makePlanModel())
        _importModel = State(initialValue: container.makeImportModel())
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
                SettingsView(importModel: importModel)
            }
        }
    }
}
