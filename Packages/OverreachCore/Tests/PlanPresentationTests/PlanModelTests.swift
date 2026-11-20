import Domain
import Fixtures
import Foundation
import PlanPresentation
import Testing

private struct CalendarRunSource: MetricsSource {
    let run: RunActivity
    var kind: DataSourceKind { run.source }
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        (start...end).contains(run.startedAt) ? [run] : []
    }
}

@MainActor
@Suite("PlanModel")
struct PlanModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell, aliases: ["sentadilla"])
    private let bench = Exercise(name: "Bench Press (Barbell)", primaryMuscles: [.chest], equipment: .barbell)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func sessions() -> [StrengthSession] {
        (1...8).map { index in
            StrengthSession(
                name: "Lower",
                startedAt: now.addingTimeInterval(-Double(index) * 3 * 86_400),
                entries: [ExerciseEntry(exerciseID: squat.id, sets: (1...3).map { _ in WorkoutSet(weightKg: 80, reps: 10, rpe: 8) })]
            )
        }
    }

    private func model(history: [StrengthSession] = [], runSources: [any MetricsSource] = []) async -> (PlanModel, TestStore) {
        let store = TestStore(exercises: [squat, bench], sessions: history)
        let fixedNow = now
        let model = PlanModel(
            profiles: store, workouts: store, exercises: store, progression: store, clock: { fixedNow },
            calendar: calendar, runSources: runSources, routines: store
        )
        await model.load()
        return (model, store)
    }

    @Test func goalKindAndPriorityLifts() async throws {
        let (model, store) = await model()
        #expect(model.goalKind == .general)
        #expect(!model.showsPriorityLifts)
        #expect(model.goalOptions.map(\.value) == TrainingGoal.Kind.allCases)

        await model.setGoal(kind: .strength)
        #expect(model.showsPriorityLifts)
        #expect(try await store.profile().goal?.kind == .strength)

        model.priorityLiftSearch = "SENTADILLA"
        #expect(model.priorityLiftRows.map(\.name) == ["Squat (Barbell)"])
        await model.togglePriorityLift(squat.id)
        #expect(model.priorityLiftCount == 1)
        #expect(model.priorityLiftRows.first?.isSelected == true)
    }

    @Test func targetDateToggleKeepsTheChosenDate() async throws {
        let (model, store) = await model()
        #expect(!model.hasTargetDate)
        let chosen = now.addingTimeInterval(70 * 86_400)

        await model.setTargetDate(chosen)
        #expect(model.hasTargetDate)
        #expect(try await store.profile().goal?.targetDate == CalendarDay(chosen, calendar: calendar))

        await model.setHasTargetDate(false)
        #expect(!model.hasTargetDate)
        #expect(try await store.profile().goal?.targetDate == nil)

        await model.setHasTargetDate(true)
        #expect(try await store.profile().goal?.targetDate == CalendarDay(chosen, calendar: calendar))
    }

    @Test func aHybridRunningGoalAndDatedSessionSurviveBackupAndReload() async throws {
        let (model, store) = await model()
        #expect(!model.showsRunningPlan)
        await model.setGoal(kind: .hybrid)
        #expect(model.showsRunningPlan)

        model.runningDraft.enabled = true
        model.runningDraft.aimsForPainFree = true
        model.runningDraft.hasTargetTime = true
        model.runningDraft.targetMinutes = 15
        #expect(model.runningGoalPace == "Goal pace 3:00 per km")
        #expect(await model.saveRunningPlan())
        var entry = model.editRunningEntry()
        entry.purpose = .intervals
        entry.minutes = 35
        entry.distanceKm = 5.25
        #expect(await model.saveRunningEntry(entry))

        let profile = try await store.profile()
        let backup = BackupDocument(createdAt: now, profile: profile)
        #expect(try BackupCodec.decode(BackupCodec.encode(backup)).profile == profile)
        await model.load()
        #expect(model.runningGoalSummary == "Run 5 km in 15:00 without pain")
        #expect(model.upcomingRunningEntries.first?.entry.purpose == .intervals)
        #expect(model.upcomingRunningEntries.first?.entry.durationMinutes == 35)
        #expect(model.upcomingRunningEntries.first?.entry.distanceMeters == 5_250)
    }

    @Test func movesTheLegacyDayWithStableIdentityAndAllowsSeveralWorkouts() async throws {
        let (model, store) = await model()
        let old = """
            {"kind":"hybrid","priorityLifts":[],"running":{"distanceMeters":5000,"aimsForPainFree":false},
            "nextRun":{"day":{"year":2026,"month":11,"day":20},"purpose":"intervals","durationMinutes":35}}
            """
        let goal = try JSONDecoder().decode(TrainingGoal.self, from: Data(old.utf8))
        #expect(goal.scheduledStrength.isEmpty)
        let original = try #require(goal.scheduledRuns.first)
        #expect(try JSONDecoder().decode(TrainingGoal.self, from: Data(old.utf8)).scheduledRuns.first?.id == original.id)
        try await store.save(AthleteProfile(goal: goal))
        await model.load()
        var moved = model.editRunningEntry(original)
        moved.date = now.addingTimeInterval(4 * 86_400)
        #expect(await model.saveRunningEntry(moved))
        var second = model.editRunningEntry()
        second.date = moved.date
        #expect(await model.saveRunningEntry(second))

        let updated = try #require(try await store.profile().goal)
        #expect(updated.nextRun == nil)
        #expect(updated.scheduledRuns.map(\.id) == [original.id, second.id])
        #expect(updated.scheduledRuns.map(\.day) == Array(repeating: CalendarDay(moved.date, calendar: calendar), count: 2))

        var rest = model.editRunningEntry()
        rest.date = moved.date
        rest.purpose = .rest
        #expect(!(await model.saveRunningEntry(rest)))
        #expect(model.errorMessage == "A running rest day must be the only entry on that date.")
    }

    @Test func requiresAnExplicitLinkAndRejectsASecondLinkToTheMirroredRun() async throws {
        let start = now.addingTimeInterval(-2 * 86_400)
        let run = RunActivity(id: "watch", source: .garmin, startedAt: start, durationSeconds: 1_200, distanceMeters: 3_000)
        let mirror = RunActivity(id: "health", source: .appleHealth, startedAt: start.addingTimeInterval(30),
                                 durationSeconds: 1_170, distanceMeters: 3_000)
        let (model, store) = await model(runSources: [CalendarRunSource(run: run), CalendarRunSource(run: mirror)])
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000))
        try await store.save(AthleteProfile(goal: goal))
        await model.load()
        var draft = model.editRunningEntry()
        draft.date = start
        #expect(await model.saveRunningEntry(draft))
        let row = try #require(model.pastRunningEntries.first)
        #expect(row.status == "No recorded run linked")

        var edit = model.editRunningEntry(row.entry)
        let choices = await model.runningCompletionChoices(for: edit)
        #expect(choices.map(\.completion.activityID) == [run.id])
        edit.completion = choices.first?.completion
        #expect(await model.saveRunningEntry(edit))
        #expect(model.pastRunningEntries.first?.status == "Completed")

        var second = model.editRunningEntry()
        second.date = start
        #expect(await model.runningCompletionChoices(for: second).isEmpty)
        second.completion = PlannedRunCompletion(mirror)
        #expect(!(await model.saveRunningEntry(second)))
        #expect(model.errorMessage == "That run is already linked to another entry.")
    }

    @Test func strengthAssignmentsShareTheCalendarAndKeepTheirIdentityWhenMoved() async throws {
        let (model, store) = await model()
        let routine = Routine(name: "Lower", exerciseIDs: [squat.id])
        try await store.save(routine)
        let day = CalendarDay(now, calendar: calendar)
        let block = TrainingBlock(focus: .strength, start: day, isDeclared: true, routineIDs: [routine.id])
        let run = PlannedRun(day: day, purpose: .easy)
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000), nextRun: run)
        try await store.save(AthleteProfile(goal: goal, declaredBlocks: [block]))
        await model.load()

        var draft = model.editStrengthEntry()
        #expect(model.strengthRoutineOptions(for: draft).map(\.value) == [routine.id])
        draft.routineID = routine.id
        #expect(await model.saveStrengthEntry(draft))
        #expect(model.upcomingCalendarRows.map(\.id) == [.strength(draft.id), .run(run.id)])

        let rest = model.editStrengthEntry()
        #expect(!(await model.saveStrengthEntry(rest)))
        let profile = await store.profile()
        let backup = BackupDocument(createdAt: now, profile: profile)
        #expect(try BackupCodec.decode(BackupCodec.encode(backup)).profile == profile)

        let entry = try #require(profile.goal?.scheduledStrength.first)
        var moved = model.editStrengthEntry(entry)
        moved.date = now.addingTimeInterval(86_400)
        #expect(await model.saveStrengthEntry(moved))
        #expect(await model.saveStrengthEntry(rest))
        #expect(model.upcomingCalendarRows.map(\.id) == [.strength(rest.id), .run(run.id), .strength(entry.id)])
        #expect(await model.removeStrengthEntry(entry.id))
        #expect(!(await model.saveStrengthEntry(moved)))
        let saved = await store.profile()
        #expect(saved.goal?.scheduledStrength.map(\.id) == [rest.id])
        #expect(saved.goal?.scheduledRuns == [run])
        #expect(saved.declaredBlocks == [block])
    }

    @Test func strengthCalendarIsAvailableWithoutARunningGoal() async {
        let (model, _) = await model()
        await model.setGoal(kind: .hybrid)
        #expect(model.showsHybridCalendar)
        #expect(!model.showsRunningCalendar)
        let rest = model.editStrengthEntry()
        #expect(await model.saveStrengthEntry(rest))
    }

    @Test func newBlockIsDeclaredAndClampedToTheAllowedLength() async throws {
        let (model, store) = await model(history: sessions())
        model.newBlockFocus = .strength
        model.newBlockWeeks = 40

        await model.startNewBlock()

        let block = try #require(try await store.profile().declaredBlocks.last)
        #expect(block.focus == .strength)
        #expect(block.plannedWeeks == model.newBlockWeeksRange.upperBound)
        #expect(model.currentBlockTitle == "Strength")
        #expect(model.currentBlockStart != nil)
    }

    @Test func detectedBlockAndPlanRowsAreDescribed() async {
        let (model, _) = await model(history: sessions())
        #expect(model.currentBlockTitle?.hasSuffix("(detected)") == true)
        #expect(model.planRows.map(\.id) == Array(0..<model.planRows.count))
        #expect(model.planRows.allSatisfy { !$0.title.isEmpty && $0.weeks > 0 })
        #expect(model.findingLines.allSatisfy { !$0.text.isEmpty && !$0.evidence.isEmpty })
        if let next = model.next {
            #expect(next.headline.contains(" block "))
            #expect(next.reasons.allSatisfy { !$0.evidence.isEmpty })
        }
    }

    @Test func withoutTrainingThereIsNoCurrentBlock() async {
        let (model, _) = await model()
        #expect(model.currentBlockTitle == nil)
    }
}
