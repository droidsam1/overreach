import Domain
import Foundation
import SwiftData

// MARK: - Records
//
// CloudKit-compatible from day one (ADR-0004): every property has a default, no unique constraints, no
// relationships. Each record stores its domain value as versioned JSON, so the domain model can evolve without
// SwiftData migrations, and the same encoding feeds the JSON backup.

@Model
final class SessionRecord {
    var id = UUID()
    var startedAt = Date.distantPast
    var payload = Data()

    init(id: UUID, startedAt: Date, payload: Data) {
        self.id = id
        self.startedAt = startedAt
        self.payload = payload
    }
}

@Model
final class ExerciseRecord {
    var id = UUID()
    var payload = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

@Model
final class CheckInRecord {
    /// `CalendarDay.description`, e.g. `2026-11-16`.
    var dayKey = ""
    var payload = Data()

    init(dayKey: String, payload: Data) {
        self.dayKey = dayKey
        self.payload = payload
    }
}

@Model
final class ProfileRecord {
    var payload = Data()

    init(payload: Data) {
        self.payload = payload
    }
}

@Model
final class ProgressionSettingsRecord {
    var exerciseID = UUID()
    var payload = Data()

    init(exerciseID: UUID, payload: Data) {
        self.exerciseID = exerciseID
        self.payload = payload
    }
}

@Model
final class RoutineRecord {
    var id = UUID()
    var payload = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

// MARK: - Container

public enum PersistenceContainer {
    /// The SwiftData container for the app. `inMemory` is for tests and previews.
    /// CloudKit stays off until the paid developer account (phase 4); turning it on is a configuration change.
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            SessionRecord.self,
            ExerciseRecord.self,
            CheckInRecord.self,
            ProfileRecord.self,
            ProgressionSettingsRecord.self,
            RoutineRecord.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// MARK: - Store

/// SwiftData implementation of the repositories. All access is serialised on this actor's model context.
@ModelActor
public actor SwiftDataStore: WorkoutRepository, ExerciseRepository, CheckInRepository, ProfileRepository,
    ProgressionSettingsRepository, RoutineRepository {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a store on `container` (see `PersistenceContainer.make`).
    public static func make(container: ModelContainer) -> SwiftDataStore {
        SwiftDataStore(modelContainer: container)
    }

    // MARK: WorkoutRepository

    public func sessions(from start: Date, to end: Date) throws -> [StrengthSession] {
        let descriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt <= end },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try modelContext.fetch(descriptor).map { try decoder.decode(StrengthSession.self, from: $0.payload) }
    }

    public func save(_ session: StrengthSession) throws {
        let id = session.id
        let payload = try encoder.encode(session)
        let existing = try modelContext.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id }))
        if let record = existing.first {
            record.startedAt = session.startedAt
            record.payload = payload
        } else {
            modelContext.insert(SessionRecord(id: id, startedAt: session.startedAt, payload: payload))
        }
        try modelContext.save()
    }

    /// One fetch for the existing records and one commit for the whole batch (imports of thousands of sets).
    public func save(_ sessions: [StrengthSession]) throws {
        guard !sessions.isEmpty else { return }
        let ids = sessions.map(\.id)
        let existing = try modelContext.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { ids.contains($0.id) }))
        var records = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for session in sessions {
            let payload = try encoder.encode(session)
            if let record = records[session.id] {
                record.startedAt = session.startedAt
                record.payload = payload
            } else {
                let record = SessionRecord(id: session.id, startedAt: session.startedAt, payload: payload)
                modelContext.insert(record)
                records[session.id] = record
            }
        }
        try modelContext.save()
    }

    public func deleteSession(id: UUID) throws {
        try modelContext.delete(model: SessionRecord.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    // MARK: ExerciseRepository

    /// The built-in catalog plus the user's exercises. A saved exercise with a built-in id overrides it
    /// (e.g. a corrected muscle mapping).
    public func allExercises() throws -> [Exercise] {
        var byID = Dictionary(ExerciseCatalog.builtIn.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in try modelContext.fetch(FetchDescriptor<ExerciseRecord>()) {
            let exercise = try decoder.decode(Exercise.self, from: record.payload)
            byID[exercise.id] = exercise
        }
        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ exercise: Exercise) throws {
        let id = exercise.id
        let payload = try encoder.encode(exercise)
        let existing = try modelContext.fetch(FetchDescriptor<ExerciseRecord>(predicate: #Predicate { $0.id == id }))
        if let record = existing.first {
            record.payload = payload
        } else {
            modelContext.insert(ExerciseRecord(id: id, payload: payload))
        }
        try modelContext.save()
    }

    /// Deletes the user's record. A built-in exercise falls back to its built-in definition.
    public func deleteExercise(id: UUID) throws {
        try modelContext.delete(model: ExerciseRecord.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    // MARK: RoutineRepository

    public func allRoutines() throws -> [Routine] {
        try modelContext.fetch(FetchDescriptor<RoutineRecord>())
            .map { try decoder.decode(Routine.self, from: $0.payload) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func save(_ routine: Routine) throws {
        let id = routine.id
        let payload = try encoder.encode(routine)
        let existing = try modelContext.fetch(FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == id }))
        if let record = existing.first {
            record.payload = payload
        } else {
            modelContext.insert(RoutineRecord(id: id, payload: payload))
        }
        try modelContext.save()
    }

    public func deleteRoutine(id: UUID) throws {
        try modelContext.delete(model: RoutineRecord.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }

    // MARK: CheckInRepository

    public func checkIn(for day: CalendarDay) throws -> CheckIn? {
        let key = day.description
        let records = try modelContext.fetch(FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.dayKey == key }))
        return try records.first.map { try decoder.decode(CheckIn.self, from: $0.payload) }
    }

    public func checkIns(in range: ClosedRange<CalendarDay>) throws -> [CheckIn] {
        let lower = range.lowerBound.description
        let upper = range.upperBound.description
        // ISO dates sort lexicographically, so the string range matches the day range.
        let descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.dayKey >= lower && $0.dayKey <= upper },
            sortBy: [SortDescriptor(\.dayKey)]
        )
        return try modelContext.fetch(descriptor).map { try decoder.decode(CheckIn.self, from: $0.payload) }
    }

    public func save(_ checkIn: CheckIn) throws {
        let key = checkIn.day.description
        let payload = try encoder.encode(checkIn)
        let existing = try modelContext.fetch(FetchDescriptor<CheckInRecord>(predicate: #Predicate { $0.dayKey == key }))
        if let record = existing.first {
            record.payload = payload
        } else {
            modelContext.insert(CheckInRecord(dayKey: key, payload: payload))
        }
        try modelContext.save()
    }

    // MARK: ProfileRepository

    public func profile() throws -> AthleteProfile {
        guard let record = try modelContext.fetch(FetchDescriptor<ProfileRecord>()).first else {
            return AthleteProfile()
        }
        return try decoder.decode(AthleteProfile.self, from: record.payload)
    }

    public func save(_ profile: AthleteProfile) throws {
        let payload = try encoder.encode(profile)
        if let record = try modelContext.fetch(FetchDescriptor<ProfileRecord>()).first {
            record.payload = payload
        } else {
            modelContext.insert(ProfileRecord(payload: payload))
        }
        try modelContext.save()
    }

    // MARK: ProgressionSettingsRepository

    public func progressionSettings(for exerciseID: UUID) throws -> ProgressionSettings? {
        let records = try modelContext.fetch(
            FetchDescriptor<ProgressionSettingsRecord>(predicate: #Predicate { $0.exerciseID == exerciseID })
        )
        return try records.first.map { try decoder.decode(ProgressionSettings.self, from: $0.payload) }
    }

    public func allProgressionSettings() throws -> [UUID: ProgressionSettings] {
        var result: [UUID: ProgressionSettings] = [:]
        for record in try modelContext.fetch(FetchDescriptor<ProgressionSettingsRecord>()) {
            result[record.exerciseID] = try decoder.decode(ProgressionSettings.self, from: record.payload)
        }
        return result
    }

    public func save(_ settings: ProgressionSettings, for exerciseID: UUID) throws {
        let payload = try encoder.encode(settings)
        let existing = try modelContext.fetch(
            FetchDescriptor<ProgressionSettingsRecord>(predicate: #Predicate { $0.exerciseID == exerciseID })
        )
        if let record = existing.first {
            record.payload = payload
        } else {
            modelContext.insert(ProgressionSettingsRecord(exerciseID: exerciseID, payload: payload))
        }
        try modelContext.save()
    }

    public func deleteProgressionSettings(for exerciseID: UUID) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<ProgressionSettingsRecord>(predicate: #Predicate { $0.exerciseID == exerciseID })
        )
        for record in existing {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
