import Domain
import Foundation
@preconcurrency import HealthKit

/// Reads recovery metrics, steps and runs from Apple Health. Queries only: the day-by-day rules live in
/// `HealthAggregation` (Domain), where they are tested.
///
/// What arrives depends on the user's devices. An Apple Watch gives HRV (SDNN), resting heart rate, sleep stages,
/// VO2max and runs; Garmin Connect writes steps, resting heart rate, sleep and activities, but no HRV (that comes
/// from `GarminSource`); an iPhone alone gives steps. HealthKit does not say whether reading was allowed: denied
/// types simply return nothing.
public struct HealthKitMetricsSource: MetricsSource, ActivitySource, CycleSource {
    public let kind: DataSourceKind = .appleHealth
    private let store = HKHealthStore()
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    static let quantities: [HKQuantityTypeIdentifier] = [
        .restingHeartRate, .heartRateVariabilitySDNN, .stepCount, .vo2Max, .respiratoryRate, .oxygenSaturation,
        .heartRate, .distanceWalkingRunning,
    ]

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        for identifier in quantities {
            types.insert(HKQuantityType(identifier))
        }
        return types
    }

    public func isAvailable() async -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Shows the Health permission sheet the first time; later calls return at once. Throws when HealthKit refuses
    /// to ask, typically because the signature lacks the HealthKit entitlement (some sideloading setups drop it).
    public func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: Self.readTypes)
    }

    public func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        // Sleep that ends on the first day started the evening before.
        let start = range.lowerBound.adding(days: -1, calendar: calendar).startDate(in: calendar)
        let end = range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let samples = HealthSamples(
            sleep: try await sleep(from: start, to: end),
            restingHeartRate: try await values(.restingHeartRate, unit: bpm, from: start, to: end),
            hrv: try await values(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end),
            vo2Max: try await values(.vo2Max, unit: HKUnit(from: "ml/kg*min"), from: start, to: end),
            respirationRate: try await values(.respiratoryRate, unit: bpm, from: start, to: end),
            oxygenSaturation: try await values(.oxygenSaturation, unit: .percent(), from: start, to: end)
                .map { TimedValue(date: $0.date, value: $0.value * 100) },
            steps: try await steps(from: start, to: end)
        )
        return HealthAggregation.dailyMetrics(from: samples, in: range, source: .appleHealth, calendar: calendar)
    }

    public func dailyActivity(in range: ClosedRange<CalendarDay>) async throws -> [DailyActivity] {
        let start = range.lowerBound.startDate(in: calendar)
        let end = range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let steps = try await steps(from: start, to: end)
        let walks = Dictionary(grouping: try await walks(from: start, to: end)) {
            CalendarDay($0.start, calendar: calendar)
        }
        return Set(steps.keys).union(walks.keys)
            .filter { range.contains($0) }
            .map { DailyActivity(day: $0, steps: steps[$0], walks: walks[$0] ?? []) }
            .sorted { $0.day < $1.day }
    }

    /// Walking and hiking workouts as walks, plus walks found in the minute-by-minute steps outside any workout
    /// (ADR-0010, `StepWalkDetection`). Detected walks use the fallback load estimate to avoid an additional
    /// query for weeks of heart-rate samples.
    private func walks(from start: Date, to end: Date) async throws -> [WalkBout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let workouts = try await query.result(for: store)
        let detected = StepWalkDetection.walks(
            stepsPerMinute: try await stepsPerMinute(from: start, to: end),
            excluding: workouts.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate)) }
        )
        return workoutWalks(workouts, bpm: bpm) + detected
    }

    private func workoutWalks(_ workouts: [HKWorkout], bpm: HKUnit) -> [WalkBout] {
        workouts
            .filter { $0.workoutActivityType == .walking || $0.workoutActivityType == .hiking }
            .map { workout in
                let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                let steps = workout.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()
                let elevation = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity
                return WalkBout(
                    start: workout.startDate,
                    durationSeconds: workout.duration,
                    steps: steps.map { Int($0.doubleValue(for: .count())) },
                    distanceMeters: distance?.doubleValue(for: .meter()),
                    averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?.doubleValue(for: bpm),
                    elevationGainMeters: elevation?.doubleValue(for: .meter()),
                    source: .appleHealth
                )
            }
    }

    public func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)], sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await query.result(for: store)
            .filter { $0.workoutActivityType == .running }
            .map { workout in
                let heartRate = workout.statistics(for: HKQuantityType(.heartRate))
                let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
                let ascent = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity
                let descent = workout.metadata?[HKMetadataKeyElevationDescended] as? HKQuantity
                return RunActivity(
                    id: workout.uuid.uuidString,
                    source: .appleHealth,
                    name: workout.sourceRevision.source.name,
                    startedAt: workout.startDate,
                    durationSeconds: workout.duration,
                    distanceMeters: distance?.doubleValue(for: .meter()) ?? 0,
                    averageHeartRate: heartRate?.averageQuantity()?.doubleValue(for: bpm),
                    maxHeartRate: heartRate?.maximumQuantity()?.doubleValue(for: bpm),
                    elevationGainMeters: ascent?.doubleValue(for: .meter()),
                    elevationLossMeters: descent?.doubleValue(for: .meter())
                )
            }
    }

    /// Menstrual flow days (ADR-0009). Read only for people who track a natural cycle, so access is asked here, on
    /// first use, instead of in everyone's Health sheet. Days logged as "no flow" are left out.
    public func menstrualEvents(in range: ClosedRange<CalendarDay>) async throws -> [MenstrualEvent] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let type = HKCategoryType(.menstrualFlow)
        try await store.requestAuthorization(toShare: [], read: [type])
        let start = range.lowerBound.startDate(in: calendar)
        let end = range.upperBound.adding(days: 1, calendar: calendar).startDate(in: calendar)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { sample in
            guard let flow = Self.flow(of: sample.value) else { return nil }
            let isStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? NSNumber)?.boolValue ?? false
            return MenstrualEvent(
                day: CalendarDay(sample.startDate, calendar: calendar), flow: flow, isCycleStart: isStart,
                source: .appleHealth
            )
        }
    }

    /// Health's flow value, or `nil` for "no flow".
    static func flow(of value: Int) -> MenstrualFlow? {
        guard let bleeding = HKCategoryValueVaginalBleeding(rawValue: value) else { return .unspecified }
        return switch bleeding {
        case .light: .light
        case .medium: .medium
        case .heavy: .heavy
        case .none: nil
        default: .unspecified
        }
    }

    // MARK: - Queries

    private func values(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date
    ) async throws -> [TimedValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).map {
            TimedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    private func sleep(from start: Date, to end: Date) async throws -> [SleepSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { sample in
            Self.stage(of: sample.value).map { SleepSample(start: sample.startDate, end: sample.endDate, stage: $0) }
        }
    }

    static func stage(of value: Int) -> SleepSample.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: .inBed
        case .asleepUnspecified: .asleep
        case .asleepCore: .light
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .awake: .awake
        default: nil
        }
    }

    /// Steps of each minute that has any, deduplicated across the iPhone and the watch by HealthKit.
    private func stepsPerMinute(from start: Date, to end: Date) async throws -> [TimedValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(minute: 1)
        )
        let collection = try await query.result(for: store)
        var result: [TimedValue] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let sum = statistics.sumQuantity()?.doubleValue(for: .count()), sum > 0 {
                result.append(TimedValue(date: statistics.startDate, value: sum))
            }
        }
        return result
    }

    private func steps(from start: Date, to end: Date) async throws -> [CalendarDay: Int] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: calendar.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await query.result(for: store)
        var result: [CalendarDay: Int] = [:]
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                result[CalendarDay(statistics.startDate, calendar: calendar)] = Int(sum.doubleValue(for: .count()))
            }
        }
        return result
    }
}
