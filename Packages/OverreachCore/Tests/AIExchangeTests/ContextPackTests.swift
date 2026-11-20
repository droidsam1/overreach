import AIExchange
import Domain
import Foundation
import Testing

@Suite("AI context pack")
struct ContextPackTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], secondaryMuscles: [.triceps],
                                 equipment: .barbell)
    private let row = Exercise(name: "Barbell Row", primaryMuscles: [.back], equipment: .barbell)
    private let curl = Exercise(name: "Curl", primaryMuscles: [.biceps], equipment: .dumbbell)

    private var period: ClosedRange<CalendarDay> {
        let today = CalendarDay(now, calendar: calendar)
        return today.adding(days: -27, calendar: calendar)...today
    }

    private func session(daysAgo: Double, reps: [Int], notes: String? = nil) -> StrengthSession {
        let start = now.addingTimeInterval(-daysAgo * 86_400)
        return StrengthSession(
            name: "Push",
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            entries: [ExerciseEntry(
                exerciseID: bench.id,
                sets: [WorkoutSet(kind: .warmup, weightKg: 40, reps: 10)]
                    + reps.map { WorkoutSet(weightKg: 60, reps: $0, rpe: 8) },
                notes: "Left shoulder"
            )],
            notes: notes,
            focus: .hypertrophy
        )
    }

    private func pack() -> ContextPack {
        var profile = AthleteProfile(sex: .male, birthYear: 1990, bodyMassKg: 80.25)
        profile.goal = TrainingGoal(kind: .strength, priorityLifts: [bench.id])
        let input = ContextInput(
            sessions: [session(daysAgo: 2, reps: [10, 10, 9], notes: "Slept badly"), session(daysAgo: 9, reps: [9, 9, 9])],
            earlierSessions: [session(daysAgo: 60, reps: [8, 8, 8])],
            exercises: [bench, row, curl],
            settings: [row.id: ProgressionSettings(scheme: .linearLoad(sets: 5, reps: 5, targetRPE: 8), incrementKg: 2.5)],
            routines: [Routine(name: "Pull", focus: .strength, exerciseIDs: [row.id])],
            profile: profile,
            checkIns: [CheckIn(day: CalendarDay(now, calendar: calendar), energy: 3, note: "Tired")],
            appVersion: "0.1.0"
        )
        return ContextPackBuilder.build(input, period: period, now: now, calendar: calendar)
    }

    @Test func identifiesItsFormatAndVersion() {
        let pack = pack()
        #expect(pack.format == "overreach.context")
        #expect(pack.version == 1)
        #expect(pack.about.contains("no instructions"))
        #expect(pack.app.version == "0.1.0")
        #expect(pack.units.weight == "kg")
    }

    @Test func sessionsAreRawDataWithNotesAndExerciseNames() throws {
        let pack = pack()
        #expect(pack.sessions.map(\.notes) == [nil, "Slept badly"])  // oldest first
        let latest = try #require(pack.sessions.last)
        #expect(latest.durationSeconds == 3_600)
        #expect(latest.focus == "hypertrophy")
        #expect(latest.exercises.first?.exercise == "Bench Press")
        #expect(latest.exercises.first?.notes == "Left shoulder")
        #expect(latest.exercises.first?.sets.first?.kind == "warmup")
        #expect(latest.exercises.first?.sets.last?.kind == nil)
        #expect(latest.exercises.first?.sets.last?.reps == 9)
    }

    @Test func onlyUsedExercisesAreDescribedButTheWholeCatalogIsListed() {
        let pack = pack()
        #expect(pack.catalog == ["Barbell Row", "Bench Press", "Curl"])
        #expect(pack.exercises.map(\.name) == ["Barbell Row", "Bench Press"])
        #expect(pack.exercises.first?.progression?.scheme.type == "linearLoad")
        #expect(pack.exercises.last?.progression == nil)
        #expect(pack.exercises.last?.secondaryMuscles == ["triceps"])
    }

    @Test func profileRoutinesAndCheckInsUseNamesAndDays() {
        let pack = pack()
        #expect(pack.athlete.goal?.kind == "strength")
        #expect(pack.athlete.goal?.priorityLifts == ["Bench Press"])
        #expect(pack.athlete.bodyMassKg == 80.3)
        #expect(pack.athlete.cycleTracking == nil)
        #expect(pack.routines.first?.exercises == ["Barbell Row"])
        #expect(pack.checkIns.first?.note == "Tired")
        #expect(pack.period.to == CalendarDay(now, calendar: calendar).description)
    }

    @Test func trendsCoverThePeriodWithTheStatusFromTheLongerHistory() throws {
        let trend = try #require(pack().exerciseTrends.first)
        #expect(trend.exercise == "Bench Press")
        #expect(trend.exposures == 2)
        #expect(trend.lastWorkingWeightKg == 60)
        #expect(trend.estimatedOneRepMaxKg.count == 2)
        #expect(["progressing", "holding", "stalled", "notEnoughData"].contains(trend.status))
    }

    @Test func jsonRoundTripsAndTheMessageWrapsIt() throws {
        let pack = pack()
        let data = try ContextMessage.json(pack)
        #expect(try ContextMessage.decode(data) == pack)

        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"format\":\"overreach.context\""))
        #expect(!json.contains("\\/"))
        let text = ContextMessage.text(json: json, request: "Help me plan my next block.")
        #expect(text.hasPrefix("Overreach training context (overreach.context v1)"))
        #expect(text.contains("```json\n{"))
        #expect(text.hasSuffix("```\n\nHelp me plan my next block."))
        #expect(ContextMessage.text(json: json, request: nil).hasSuffix("```"))
    }

    @Test func anEmptyHistoryStillMakesAValidPack() throws {
        let pack = ContextPackBuilder.build(ContextInput(), period: period, now: now, calendar: calendar)
        #expect(pack.sessions.isEmpty)
        #expect(pack.athlete.goal == nil)
        #expect(try ContextMessage.decode(ContextMessage.json(pack)) == pack)
    }

    @Test func aSessionTheWatchRecordedCarriesItsHeartRateAndLoad() throws {
        let recorded = session(daysAgo: 2, reps: [10])
        let alone = session(daysAgo: 9, reps: [9])
        let garmin = RecordedStrengthActivity(
            id: "g1", source: .garmin, startedAt: recorded.startedAt.addingTimeInterval(-60), durationSeconds: 3_660,
            averageHeartRate: 111.6, maxHeartRate: 149.2, trainingLoad: 47.84, aerobicTrainingEffect: 2.14,
            anaerobicTrainingEffect: 1.76
        )
        let healthCopy = RecordedStrengthActivity(
            id: "h1", source: .appleHealth, startedAt: recorded.startedAt, durationSeconds: 3_600
        )
        let input = ContextInput(
            sessions: [recorded, alone], exercises: [bench], strengthRecordings: [healthCopy, garmin]
        )

        let pack = ContextPackBuilder.build(input, period: period, now: now, calendar: calendar)

        let shared = try #require(pack.sessions.first { $0.id == recorded.id.uuidString })
        #expect(shared.watch == ContextPack.Watch(
            source: "garmin", averageHeartRate: 112, maxHeartRate: 149, trainingLoad: 47.8,
            aerobicTrainingEffect: 2.1, anaerobicTrainingEffect: 1.8
        ))
        #expect(pack.sessions.first { $0.id == alone.id.uuidString }?.watch == nil)
        let json = String(decoding: try ContextMessage.json(pack), as: UTF8.self)
        #expect(json.contains("\"watch\""))
        #expect(pack.version == 1)  // an optional field keeps the version (docs/ai-exchange.md)
    }
}

