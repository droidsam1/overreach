import Domain
import Foundation
@preconcurrency import HealthKit

/// Writes strength sessions to Apple Health as traditional strength training workouts (ADR-0016).
///
/// Each workout carries the session id in `HKMetadataKeyExternalUUID`. HealthKit workouts cannot be changed, so
/// saving again writes a new workout and then removes the ones already written for that session.
public struct HealthKitWorkoutWriter: HealthWorkoutWriter, RecordedStrengthSource {
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

    /// Strength workouts written by other apps (e.g. Garmin Connect) in the range. Needs read permission for workouts,
    /// which the metrics source asks for; without it HealthKit returns only this app's own workouts, which are skipped.
    public func strengthWorkoutsFromOtherSources(
        from start: Date, to end: Date
    ) async throws -> [RecordedStrengthActivity] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let strength = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .traditionalStrengthTraining),
            HKQuery.predicateForWorkouts(with: .functionalStrengthTraining),
        ])
        let range = HKQuery.predicateForSamples(withStart: start, end: end)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [strength, range])
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
        let ownBundle = HKSource.default().bundleIdentifier
        return try await query.result(for: store)
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
            .map { workout in
                RecordedStrengthActivity(
                    id: workout.uuid.uuidString,
                    source: .appleHealth,
                    startedAt: workout.startDate,
                    durationSeconds: workout.duration,
                    averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())),
                    maxHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?
                        .maximumQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
                )
            }
    }

    /// The same workouts, as recordings to show next to logged sessions (Apple Watch Workout app, Garmin's copy).
    public func strengthActivities(from start: Date, to end: Date) async -> [RecordedStrengthActivity] {
        (try? await strengthWorkoutsFromOtherSources(from: start, to: end)) ?? []
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
