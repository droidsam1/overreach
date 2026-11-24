import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

/// Check-ins kept in memory; `failing` makes saves throw.
actor CheckInStore: CheckInRepository {
    struct Failure: Error {}
    private(set) var byDay: [CalendarDay: CheckIn] = [:]
    private let failing: Bool

    init(_ checkIns: [CheckIn] = [], failing: Bool = false) {
        byDay = Dictionary(checkIns.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        self.failing = failing
    }

    func checkIn(for day: CalendarDay) async throws -> CheckIn? { byDay[day] }
    func checkIns(in range: ClosedRange<CalendarDay>) async throws -> [CheckIn] {
        byDay.values.filter { range.contains($0.day) }.sorted { $0.day < $1.day }
    }
    func save(_ checkIn: CheckIn) async throws {
        if failing { throw Failure() }
        byDay[checkIn.day] = checkIn
    }
}

/// Counts backups requested after saving.
private actor BackupSpy: BackupService {
    private(set) var backUps = 0

    func isConfigured() async -> Bool { true }
    func folderName() async -> String? { "Backups" }
    func configure(folder: URL) async throws {}
    func backUp(now: Date) async throws -> BackupSummary { throw CancellationError() }
    func backUpIfConfigured(now: Date) async -> Bool {
        backUps += 1
        return true
    }
    func exportData(now: Date) async throws -> Data { Data() }
    func latestBackup() async throws -> BackupDocument? { nil }
    func restore(from data: Data) async throws -> BackupSummary { throw CancellationError() }
    func hasUserData() async throws -> Bool { true }
}

private struct NoMetrics: MetricsSource {
    let kind = DataSourceKind.appleHealth
    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] { [] }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

private struct CheckInProfile: ProfileRepository {
    let stored: AthleteProfile
    func profile() async throws -> AthleteProfile { stored }
    func save(_ profile: AthleteProfile) async throws {}
}

private struct LowHRVMetrics: MetricsSource {
    let kind = DataSourceKind.garmin
    let today: CalendarDay
    let calendar: Calendar
    let elevatedPulse: Bool

    func isAvailable() async -> Bool { true }
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        (0...25).map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.hrvRMSSDMs = offset < 7 ? 35 : 55
            metrics.restingHeartRate = offset == 0 && elevatedPulse ? 59 : 50
            return metrics
        }.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] { [] }
}

@MainActor
@Suite("Daily check-in")
struct CheckInModelTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private var today: CalendarDay { CalendarDay(now, calendar: calendar) }

    @Test func anEmptyCheckInCannotBeSaved() {
        let model = CheckInModel(day: today, existing: nil, checkIns: CheckInStore())

        #expect(!model.canSave)
        model.energy = 4
        #expect(model.canSave)
    }

    @Test func savesTheAnswersAndBacksUp() async {
        let store = CheckInStore()
        let backup = BackupSpy()
        let model = CheckInModel(day: today, existing: nil, checkIns: store, backup: backup)
        model.energy = 2
        model.soreness = 3
        model.note = "  Slept badly  "

        #expect(await model.save())

        #expect(await store.byDay[today] == CheckIn(day: today, energy: 2, soreness: 3, note: "Slept badly"))
        #expect(await backup.backUps == 1)
        #expect(model.errorMessage == nil)
    }

    @Test func warmupAnswerCanBeEditedAndSurvivesBackup() async throws {
        let store = CheckInStore()
        let model = CheckInModel(day: today, existing: nil, checkIns: store, asksAboutLegResponse: true)
        #expect(model.legResponseOptions.map(\.value) == [.normal, .heavy, .limited, .notWarmedUp, .skipped])
        model.legResponse = .notWarmedUp
        #expect(await model.save())
        let saved = try #require(await store.byDay[today])
        let backup = BackupDocument(createdAt: now, checkIns: [saved])
        let restored = try #require(BackupCodec.decode(BackupCodec.encode(backup)).checkIns.first)
        let edit = CheckInModel(day: today, existing: restored, checkIns: store)
        #expect(edit.legResponseQuestionTitle == model.legResponseQuestionTitle)
        #expect(edit.legResponse == .notWarmedUp)
        edit.legResponse = .heavy
        #expect(await edit.save())
        #expect(await store.byDay[today]?.legResponse == .heavy)
    }

    @Test func editingStartsFromTodaysCheckInAndNeedsAChange() {
        let existing = CheckIn(day: today, isSick: true, note: "Flu")
        let model = CheckInModel(day: today, existing: existing, checkIns: CheckInStore([existing]))

        #expect(model.isSick)
        #expect(model.note == "Flu")
        #expect(!model.canSave)
        model.isSick = false
        #expect(model.canSave)
    }

    @Test func aFailedSaveKeepsTheSheetOpen() async {
        let model = CheckInModel(day: today, existing: nil, checkIns: CheckInStore(failing: true))
        model.isSick = true

        #expect(!(await model.save()))
        #expect(model.errorMessage == "Could not save your check-in.")
    }

    @Test func offersEveryAnswerOnTheStoredScales() {
        let model = CheckInModel(day: today, existing: nil, checkIns: CheckInStore())

        #expect(model.energyOptions.map(\.value) == [1, 2, 3, 4, 5])
        #expect(model.sorenessOptions.map(\.value) == [0, 1, 2, 3])
    }

    @Test func todayOpensTheCheckInAndShowsWhatItSaid() async throws {
        let store = CheckInStore()
        let model = TodayModel(sources: [NoMetrics()], checkIns: store, calendar: calendar)
        await model.load(now: now)
        #expect(model.showsCheckIn)
        #expect(model.checkInButtonTitle == "How do you feel today?")
        #expect(model.checkInSummary == nil)

        let sheet = try #require(model.makeCheckInModel(now: now))
        sheet.energy = 4
        sheet.soreness = 1
        #expect(await sheet.save())
        await model.load(now: now)

        #expect(model.checkInButtonTitle == "Edit today's check-in")
        #expect(model.checkInSummary == "Energy 4/5 · Soreness 1/3")
        #expect(model.readinessLevel == .green)
        #expect(model.makeCheckInModel(now: now)?.energy == 4)
    }

    @Test func withoutAStoreThereIsNoCheckIn() {
        let model = TodayModel(sources: [], calendar: calendar)

        #expect(!model.showsCheckIn)
        #expect(model.makeCheckInModel(now: now) == nil)
    }

    @Test func lowHRVAsksAboutStressAndKeepsItAsContext() async throws {
        let source = LowHRVMetrics(today: today, calendar: calendar, elevatedPulse: false)
        let store = CheckInStore()
        let model = TodayModel(sources: [source], checkIns: store, calendar: calendar)
        await model.load(now: now)
        let original = model.readiness
        #expect(model.checkInButtonTitle == "Have you felt more stressed than usual lately?")

        let sheet = try #require(model.makeCheckInModel(now: now))
        #expect(sheet.contextQuestionTitle == model.checkInButtonTitle)
        #expect(sheet.contextOptions.map(\.value) == [.yes, .no, .unsure, .skipped])
        sheet.contextAnswer = .yes
        #expect(await sheet.save())
        await model.load(now: now)

        #expect(model.readiness.level == original.level)
        #expect(model.readiness.reasons == original.reasons + [.unusualStress])
        #expect(model.checkInSummary == "More stress than usual")
        #expect(model.checkInButtonTitle == "Edit today's check-in")
        #expect(model.makeCheckInModel(now: now)?.contextAnswer == .yes)
    }

    @Test func elevatedPulsePromptsSymptomsAndAnAnswerCanBeCorrected() async throws {
        let source = LowHRVMetrics(today: today, calendar: calendar, elevatedPulse: true)
        let model = TodayModel(sources: [source], checkIns: CheckInStore(), calendar: calendar)
        await model.load(now: now)
        let initialReadiness = model.readiness
        #expect(model.checkInButtonTitle == "Do new symptoms make you feel too unwell to train today?")
        #expect(model.readinessSummary?.contains("comparable readings low") == true)
        #expect(model.readinessSummary?.contains("bpm above your usual") == false)
        #expect(model.readinessLines.contains { $0.text.contains("bpm above your usual") })

        let sheet = try #require(model.makeCheckInModel(now: now))
        sheet.contextAnswer = .yes
        #expect(await sheet.save())
        await model.load(now: now)

        #expect(model.readiness.reasons == [.symptomsLimitTraining])
        #expect(model.readinessAdvice == "Skip training today and reassess how you feel.")
        #expect(model.readinessSummary == "You reported symptoms that make you feel too unwell to train.")
        #expect(model.readinessObservations.isEmpty)
        #expect(model.readinessSources.isEmpty)
        #expect(model.checkIn?.isSick == false)

        let edit = try #require(model.makeCheckInModel(now: now))
        edit.contextAnswer = .no
        #expect(await edit.save())
        await model.load(now: now)

        #expect(model.readiness.level == initialReadiness.level && model.readiness.reasons == initialReadiness.reasons)
        #expect(model.checkInButtonTitle == "Edit today's check-in")
        #expect(model.makeCheckInModel(now: now.addingTimeInterval(86_400))?.contextQuestionTitle == nil)
    }

    @Test func skippingCanBeSavedWithoutChangingTheAdvice() async throws {
        let source = LowHRVMetrics(today: today, calendar: calendar, elevatedPulse: false)
        let model = TodayModel(sources: [source], checkIns: CheckInStore(), calendar: calendar)
        await model.load(now: now)
        let original = model.readiness
        let sheet = try #require(model.makeCheckInModel(now: now))
        sheet.contextAnswer = .skipped
        #expect(await sheet.save())
        await model.load(now: now)

        #expect(model.readiness.level == original.level && model.readiness.reasons == original.reasons)
        #expect(model.checkInSummary == nil)
        #expect(model.checkInButtonTitle == "Edit today's check-in")
    }

    @Test func warningSignsTakePrecedenceAndCanBeCleared() async throws {
        let store = CheckInStore()
        let model = TodayModel(sources: [], checkIns: store, calendar: calendar)
        await model.load(now: now)
        let sheet = try #require(model.makeCheckInModel(now: now))
        sheet.hasExerciseWarningSigns = true
        #expect(await sheet.save())
        await model.load(now: now)

        #expect(model.readiness.reasons == [.exerciseWarningSigns])
        #expect(model.readinessAdvice == "Skip training and seek medical advice before returning to exercise.")
        let tomorrow = try #require(model.makeCheckInModel(now: now.addingTimeInterval(86_400)))
        #expect(!tomorrow.hasExerciseWarningSigns)

        let edit = try #require(model.makeCheckInModel(now: now))
        edit.hasExerciseWarningSigns = false
        #expect(await edit.save())
        await model.load(now: now)
        #expect(model.readinessLevel == .unknown)
    }

    @Test func recentLinkedRunPainPromptsAQuestionAndChangesAdvice() async throws {
        let startedAt = now.addingTimeInterval(-1_800)
        var completion = PlannedRunCompletion(RunActivity(
            id: "run", source: .garmin, startedAt: startedAt, durationSeconds: 900, distanceMeters: 2_000
        ))
        completion.painAfter = true
        let goal = TrainingGoal(kind: .hybrid, running: RunningGoal(distanceMeters: 5_000),
                                nextRun: PlannedRun(day: today, purpose: .easy, completion: completion))
        let model = TodayModel(sources: [], checkIns: CheckInStore(),
                               profiles: CheckInProfile(stored: AthleteProfile(goal: goal)), calendar: calendar)
        await model.load(now: now)
        let sheet = try #require(model.makeCheckInModel(now: now))
        #expect(sheet.contextQuestionTitle == "Did the pain get worse or change your stride on your last run?")
        sheet.contextAnswer = .yes
        #expect(await sheet.save())
        await model.load(now: now)
        #expect(model.readiness.reasons == [.runningPainLimitsTraining])
        #expect(model.runningOption == nil)
    }

    @Test func warningSignsHideStrengthChoices() async throws {
        let squat = Exercise(name: "Squat", primaryMuscles: [.quadriceps], equipment: .barbell)
        let bench = Exercise(name: "Bench Press", primaryMuscles: [.chest], equipment: .barbell)
        let sessions = [squat, bench].enumerated().map { index, exercise in
            let start = now.addingTimeInterval(-Double(index + 1) * 86_400)
            return StrengthSession(
                name: exercise.name, startedAt: start, endedAt: start.addingTimeInterval(3_600),
                entries: [ExerciseEntry(exerciseID: exercise.id, sets: [WorkoutSet(weightKg: 45, reps: 6)])]
            )
        }
        let workouts = TestStore(exercises: [squat, bench], sessions: sessions)
        let checkIns = CheckInStore()
        let model = TodayModel(sources: [], checkIns: checkIns, workouts: workouts, calendar: calendar)
        await model.load(now: now)
        #expect(model.strengthChoices.count == 2)

        try await checkIns.save(CheckIn(day: today, exerciseWarningSigns: true))
        await model.load(now: now)
        #expect(model.strengthChoices.isEmpty)
        #expect(model.strengthChoiceNote == nil)
    }

    @Test(arguments: [CheckIn.Context.Question.symptoms, .stress, .fatigue, .runningPain])
    func theOptionalAnswerRoundTripsThroughBackup(question: CheckIn.Context.Question) throws {
        let checkIn = CheckIn(
            day: today, context: .init(question: question, answer: .unsure), exerciseWarningSigns: true
        )
        let encoded = try BackupCodec.encode(BackupDocument(createdAt: now, checkIns: [checkIn]))
        let decoded = try BackupCodec.decode(encoded)

        #expect(decoded.checkIns == [checkIn])
        #expect(decoded.formatVersion == BackupDocument.currentFormatVersion)
    }
}
