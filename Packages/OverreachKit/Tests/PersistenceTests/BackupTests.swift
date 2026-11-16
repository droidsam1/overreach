import Domain
import Foundation
import Persistence
import Testing

/// Keeps the "folder" in memory.
private actor MemoryDestination: BackupDestination {
    private(set) var files: [Date: Data] = [:]
    private var configured: Bool

    init(configured: Bool = true) {
        self.configured = configured
    }

    func isConfigured() -> Bool { configured }
    func folderName() -> String? { configured ? "Memory" : nil }
    func configure(folder: URL) { configured = true }
    func write(_ data: Data, at date: Date) { files[date] = data }
    func latest() -> Data? { files.max { $0.key < $1.key }?.value }
}

private func makeService(store: InMemoryStore, destination: any BackupDestination) -> RepositoryBackupService {
    RepositoryBackupService(
        workouts: store, exercises: store, checkIns: store, profiles: store, progression: store,
        destination: destination, appVersion: "test"
    )
}

@Suite("Backup service")
struct BackupServiceTests {
    private let custom = Exercise(name: "Zercher Squat", primaryMuscles: [.quadriceps], equipment: .barbell, isCustom: true)

    private func populatedStore() async -> InMemoryStore {
        let store = InMemoryStore(exercises: ExerciseCatalog.builtIn + [custom])
        await store.save(StrengthSession(
            name: "Legs",
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            entries: [ExerciseEntry(exerciseID: custom.id, sets: [WorkoutSet(weightKg: 100, reps: 5)])]
        ))
        await store.save(CheckIn(day: CalendarDay(year: 2026, month: 11, day: 16), energy: 4))
        await store.save(ProgressionSettings(incrementKg: 1.25, focus: .strength), for: custom.id)
        await store.save(AthleteProfile(goal: TrainingGoal(kind: .strength)))
        return store
    }

    @Test func backUpThenRestoreIntoAFreshStore() async throws {
        let source = await populatedStore()
        let destination = MemoryDestination()
        let summary = try await makeService(store: source, destination: destination)
            .backUp(now: Date(timeIntervalSince1970: 1_790_100_000))
        #expect(summary.sessions == 1)
        #expect(summary.exercises == 1)  // only the custom exercise, not the catalog

        let fresh = InMemoryStore(exercises: ExerciseCatalog.builtIn)
        let restoring = makeService(store: fresh, destination: destination)
        #expect(try await restoring.hasUserData() == false)
        let latest = try #require(await destination.latest())
        _ = try await restoring.restore(from: latest)
        _ = try await restoring.restore(from: latest)  // twice: still no duplicates

        #expect(try await fresh.sessions(from: .distantPast, to: .distantFuture)
            == source.sessions(from: .distantPast, to: .distantFuture))
        #expect(try await fresh.allExercises().count == ExerciseCatalog.builtIn.count + 1)
        #expect(try await fresh.progressionSettings(for: custom.id)?.incrementKg == 1.25)
        #expect(try await fresh.profile().goal?.kind == .strength)
        #expect(try await restoring.hasUserData())
    }

    @Test func doesNotOverwriteAProfileAlreadySetUp() async throws {
        let source = await populatedStore()
        let data = try await makeService(store: source, destination: MemoryDestination()).exportData(now: .now)
        let target = InMemoryStore()
        await target.save(AthleteProfile(goal: TrainingGoal(kind: .hypertrophy)))
        _ = try await makeService(store: target, destination: MemoryDestination()).restore(from: data)
        #expect(try await target.profile().goal?.kind == .hypertrophy)
    }

    @Test func neverReplacesABackupWithAnEmptyOne() async throws {
        let destination = MemoryDestination()
        _ = try await makeService(store: await populatedStore(), destination: destination).backUp(now: .now)

        let empty = makeService(store: InMemoryStore(), destination: destination)
        await #expect(throws: BackupError.wouldOverwriteWithEmpty) {
            try await empty.backUp(now: .now)
        }
        #expect(await empty.backUpIfConfigured(now: .now) == false)
        #expect(try await empty.latestBackup()?.sessions.count == 1)
    }

    @Test func automaticBackupIsSkippedWithoutAFolder() async {
        let service = makeService(store: InMemoryStore(), destination: MemoryDestination(configured: false))
        #expect(await service.backUpIfConfigured(now: .now) == false)
    }
}

@Suite("Folder backup destination")
struct FolderBackupDestinationTests {
    @Test func writesLatestAndKeepsALimitedHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "backup-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let destination = FolderBackupDestination(defaultsSuite: suite, datedCopiesToKeep: 2)
        #expect(await destination.isConfigured() == false)
        try await destination.configure(folder: folder)
        #expect(await destination.isConfigured())

        for day in 0..<4 {
            try await destination.write(Data("backup \(day)".utf8), at: Date(timeIntervalSince1970: 1_790_000_000 + Double(day) * 86_400))
        }
        let latest = try #require(try await destination.latest())
        #expect(String(decoding: latest, as: UTF8.self) == "backup 3")

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.filter { $0.hasPrefix("Overreach-backup-") }.count == 2)
        #expect(files.contains(BackupCodec.fileName))
    }
}
