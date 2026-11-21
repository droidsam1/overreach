import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

/// The next strength session without a plan: a detected A-B-C-D rotation, the athlete's own choice, and how a
/// deload applies to it.
@MainActor
@Suite("Today's next strength session")
struct TodayNextSessionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private let format = Format(locale: Locale(identifier: "en_US"))
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }
    private let squat = Exercise(name: "Back Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)

    /// Workouts A to D every second day, oldest first, ending two days ago.
    private func rotation(_ names: [String]) -> [StrengthSession] {
        names.enumerated().map { index, name in
            let start = now.addingTimeInterval(-Double(names.count - index) * 2 * 86_400)
            let exercise = name == "A" || name == "C" ? squat : bench
            return StrengthSession(
                name: name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
                entries: [ExerciseEntry(exerciseID: exercise.id,
                                        sets: Array(repeating: WorkoutSet(weightKg: 100, reps: 6, rpe: 7), count: 4))]
            )
        }
    }

    /// Short sleep makes the light amber, which offers the easy strength option.
    private var amber: AmberSource { AmberSource(day: today) }

    @Test func aDetectedRotationOffersTheNextWorkoutNotTheLastOne() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(["A", "B", "C", "D", "A", "B", "C", "D"]))
        let model = TodayModel(sources: [amber], workouts: store, exercises: store, calendar: calendar, format: format)
        await model.load(now: now)

        let option = try #require(model.strengthOption)
        #expect(option.heading == "Next in your rotation · A")
        #expect(option.exerciseRows.map(\.title) == ["Back Squat"])
        #expect(model.strengthChoices.map(\.title) == ["A", "B", "C", "D"])
        #expect(model.strengthChoices.first?.isSelected == true)
        #expect(model.strengthChoiceNote == "You rotate through A → B → C → D. Next up: A.")
    }

    @Test func theAthleteCanSayWhichSessionComesNext() async throws {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(["A", "B", "C", "D", "A", "B"]))
        let model = TodayModel(sources: [amber], workouts: store, exercises: store, calendar: calendar, format: format)
        await model.load(now: now)

        #expect(model.strengthOption?.heading == "Based on a recent session · B")
        #expect(model.strengthChoices.map(\.title) == ["B", "A", "D", "C"])
        #expect(model.strengthChoiceNote
            == "Your recent sessions don't follow a fixed order yet. Choose the one you plan to do.")

        let chosen = try #require(model.strengthChoices.first { $0.title == "C" })
        model.chooseStrengthSession(chosen.id)
        #expect(model.strengthOption?.heading == "Your choice · C")
        #expect(model.strengthOption?.exerciseRows.map(\.title) == ["Back Squat"])
        #expect(model.strengthChoices.first { $0.isSelected }?.title == "C")
    }

    @Test func oneRecordedWorkoutOffersNoChoice() async {
        let store = TestStore(exercises: [squat, bench], sessions: rotation(["A"]))
        let model = TodayModel(sources: [amber], workouts: store, exercises: store, calendar: calendar, format: format)
        await model.load(now: now)

        #expect(model.strengthChoices.isEmpty)
        #expect(model.strengthChoiceNote == nil)
    }

    @Test func aDeclaredPlanNeedsNoChoice() async throws {
        let upper = Routine(name: "Upper", exerciseIDs: [bench.id])
        let store = TestStore(exercises: [squat, bench], sessions: rotation(["A", "B", "A", "B"]), routines: [upper])
        let block = TrainingBlock(focus: .strength, start: today.adding(days: -3, calendar: calendar), plannedWeeks: 6,
                                  isDeclared: true, routineIDs: [upper.id])
        try await store.save(AthleteProfile(declaredBlocks: [block]))
        let model = TodayModel(sources: [amber], profiles: store, workouts: store, exercises: store, routines: store,
                               calendar: calendar, format: format)
        await model.load(now: now)

        #expect(model.strengthChoices.isEmpty)
    }
}

/// Seven nights of 5 h sleep and nothing else: an amber light.
private struct AmberSource: MetricsSource {
    let kind = DataSourceKind.appleHealth
    let day: CalendarDay

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        var metrics = DailyMetrics(day: day, sources: [.appleHealth])
        metrics.sleepSeconds = 5 * 3_600
        return [metrics]
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}
