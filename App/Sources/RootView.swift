import FeatureHistory
import FeatureSettings
import FeatureToday
import FeatureTrends
import FeatureWorkout
import SwiftUI

/// Top-level navigation. Cross-feature navigation is wired here, never inside a feature.
struct RootView: View {
    @State private var todayModel: TodayModel

    init(container: AppContainer) {
        _todayModel = State(initialValue: container.makeTodayModel())
    }

    var body: some View {
        TabView {
            Tab("Today", systemImage: "gauge.with.needle") {
                TodayView(model: todayModel)
            }
            Tab("Train", systemImage: "dumbbell") {
                WorkoutView()
            }
            Tab("History", systemImage: "calendar") {
                HistoryView()
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
