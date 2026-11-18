import Domain
import Foundation
@preconcurrency import HealthKit

/// Writes strength sessions to Apple Health as traditional strength training workouts (ADR-0016).
///
/// Each workout carries the session id in `HKMetadataKeyExternalUUID`. HealthKit workouts cannot be changed, so
/// saving again writes a new workout and then removes the ones already written for that session.
public struct HealthKitWorkoutWriter: HealthWorkoutWriter {
    private let store = HKHealthStore()

    public init() {}

    public func saveWorkout(for session: StrengthSession) async throws {
        guard HKHealthStore.isHealthDataAvailable(), let end = session.endedAt else { return }
        // Shows the permission sheet only the first time.
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        guard canWrite else { return }
        let previous = try await workouts(forSessionID: session.id)
        try await write(session, end: end)
        if !previous.isEmpty {
            try await store.delete(previous)
        }
    }

    public func deleteWorkout(forSessionID sessionID: UUID) async throws {
        guard HKHealthStore.isHealthDataAvailable(), canWrite else { return }
        let written = try await workouts(forSessionID: sessionID)
        if !written.isEmpty {
            try await store.delete(written)
        }
    }

    private var canWrite: Bool {
        store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    private func write(_ session: StrengthSession, end: Date) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: session.startedAt)
        do {
            try await builder.addMetadata([HKMetadataKeyExternalUUID: session.id.uuidString])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            builder.discardWorkout()
            throw error
        }
    }

    /// Without read permission HealthKit still returns what this app wrote, which is all that is needed here.
    private func workouts(forSessionID sessionID: UUID) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [sessionID.uuidString]
        )
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
        return try await query.result(for: store)
    }
}
