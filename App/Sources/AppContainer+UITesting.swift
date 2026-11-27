import Domain
import Foundation
import Persistence

extension AppContainer {
    /// Launch argument the UI tests (`App/UITests`) pass to get `uiTesting()`.
    static let uiTestingArgument = "-ui-testing"

    static let uiTestingSuite = "overreach.ui-testing"

    static var isUITesting: Bool { CommandLine.arguments.contains(uiTestingArgument) }

    /// Deterministic wiring for UI tests: the built-in exercises in memory, no Health, Garmin or weather, and the
    /// setup and release notes already seen, so a test starts on Today and nothing is saved on the device.
    static func uiTesting() -> AppContainer {
        let suite = uiTestingSuite
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let status = DefaultsOnboardingStatus(suiteName: suite)
        status.markOnboardingCompleted()
        status.markReleaseNotesSeen(version: appVersion ?? "")
        let exercises = ExerciseCatalog.builtIn
        var profile = AthleteProfile()
        var routines: [Routine] = []
        if CommandLine.arguments.contains("-ui-testing-plan"),
           let squat = exercises.first(where: { $0.name == "Squat (Barbell)" }) {
            let routine = Routine(name: "Lower", exerciseIDs: [squat.id])
            routines = [routine]
            profile.declaredBlocks = [
                TrainingBlock(
                    focus: .strength, start: CalendarDay(Date()), plannedWeeks: 6,
                    isDeclared: true, routineIDs: [routine.id]
                ),
            ]
        }
        let store = InMemoryStore(exercises: exercises, profile: profile, routines: routines)
        return AppContainer(
            workouts: store, exercises: store, checkIns: store, progression: store, profiles: store,
            routines: store, onboardingStatus: status, metricsSources: []
        )
    }
}
