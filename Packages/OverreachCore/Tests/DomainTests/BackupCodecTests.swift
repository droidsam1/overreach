import Domain
import Foundation
import Testing

@Suite("Backup codec")
struct BackupCodecTests {
    private func sampleDocument() -> BackupDocument {
        let custom = Exercise(name: "Zercher Squat", primaryMuscles: [.quadriceps], equipment: .barbell, isCustom: true)
        let session = StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 1_790_000_123.456),
            endedAt: Date(timeIntervalSince1970: 1_790_003_000),
            entries: [ExerciseEntry(exerciseID: custom.id, sets: [WorkoutSet(weightKg: 100, reps: 5, rpe: 8)])],
            focus: .strength
        )
        return BackupDocument(
            createdAt: Date(timeIntervalSince1970: 1_790_010_000),
            appVersion: "0.1.0",
            sessions: [session],
            exercises: [custom],
            checkIns: [CheckIn(day: CalendarDay(year: 2026, month: 11, day: 16), energy: 4)],
            profile: AthleteProfile(sex: .male, goal: TrainingGoal(kind: .strength, priorityLifts: [custom.id])),
            progressionSettings: [ProgressionSettingsEntry(
                exerciseID: custom.id, settings: ProgressionSettings(incrementKg: 2.5, isMainLift: true, focus: .strength)
            )],
            routines: [Routine(name: "Legs", focus: .strength, exerciseIDs: [custom.id])]
        )
    }

    @Test func roundTripsExactly() throws {
        let document = sampleDocument()
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded == document)
        #expect(decoded.summary.sessions == 1)
    }

    @Test func oldBackupsWithMissingSectionsStillLoad() throws {
        let minimal = Data(#"{"formatVersion": 1, "createdAt": 0}"#.utf8)
        let decoded = try BackupCodec.decode(minimal)
        #expect(decoded.sessions.isEmpty)
        #expect(decoded.profile == AthleteProfile())
        #expect(decoded.routines.isEmpty)
    }

    @Test func rejectsNewerFormatsAndOtherFiles() {
        #expect(throws: BackupError.newerFormat(99)) {
            try BackupCodec.decode(Data(#"{"formatVersion": 99, "createdAt": 0}"#.utf8))
        }
        #expect(throws: BackupError.notABackup) {
            try BackupCodec.decode(Data("Date,Exercise Name\n".utf8))
        }
    }

    @Test func exportsOnlyCustomOrChangedExercises() {
        var changed = ExerciseCatalog.builtIn[0]
        changed.secondaryMuscles.insert(.core)
        let custom = Exercise(name: "Mine", primaryMuscles: [.chest], isCustom: true)
        let all = [changed, custom] + ExerciseCatalog.builtIn.dropFirst()
        let exported = BackupCodec.exportableExercises(all: all)
        #expect(Set(exported.map(\.id)) == [changed.id, custom.id])
    }

    @Test func datedFileNameUsesTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let name = BackupCodec.datedFileName(for: Date(timeIntervalSince1970: 1_790_000_000), calendar: calendar)
        #expect(name.hasPrefix("Overreach-backup-2026-"))
        #expect(name.hasSuffix(".json"))
    }

    @Test func rotationAdjustmentsRoundTripAndOldProfilesHaveNone() throws {
        var document = sampleDocument()
        #expect(document.profile.rotationAdjustments.isEmpty)
        document.profile.record(RotationAdjustment(
            day: CalendarDay(year: 2026, month: 11, day: 18), kind: .swap(from: "b", to: "c"), reason: .runCarryover
        ))
        document.profile.record(RotationAdjustment(
            day: CalendarDay(year: 2026, month: 11, day: 20), kind: .postpone(days: 1)
        ))
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        #expect(decoded == document)
        #expect(decoded.profile.rotationAdjustments.count == 2)

        let withoutField = Data(#"{"formatVersion": 1, "createdAt": 0, "profile": {"cycleTracking": "off"}}"#.utf8)
        #expect(try BackupCodec.decode(withoutField).profile.rotationAdjustments.isEmpty)
    }

    @Test func recordingTheSameAdjustmentTwiceKeepsOne() {
        var profile = AthleteProfile()
        let adjustment = RotationAdjustment(day: CalendarDay(year: 2026, month: 11, day: 18), kind: .postpone(days: 1))
        profile.record(adjustment)
        profile.record(adjustment)
        #expect(profile.rotationAdjustments == [adjustment])
    }
}
