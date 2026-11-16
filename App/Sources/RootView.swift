import FeatureHistory
import FeatureSettings
import FeatureToday
import FeatureTrends
import FeatureWorkout
import SwiftUI

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    @State private var todayModel: TodayModel
    @State private var workoutModel: WorkoutModel
    @State private var historyModel: HistoryModel

    init(container: AppContainer) {
        _todayModel = State(initialValue: container.makeTodayModel())
        _workoutModel = State(initialValue: container.makeWorkoutModel())
        _historyModel = State(initialValue: container.makeHistoryModel())
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
            Tab("Trends", systemImage: "chart.xyaxis.line") {
                TrendsView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
