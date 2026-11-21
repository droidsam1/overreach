import Domain
import Foundation

extension EverydayMovement {
    public struct WalkingLoad: Hashable, Sendable {
        public let dailyLoad: DailyLoad
        public let extraMinutes: Double
        public let baselineMinutes: Double
        public var evidence: EvidenceReference { MovementEvidence.walkingAboveBaseline }
    }

    public struct LoadSettings: Hashable, Sendable {
        /// Estimated effort for walks without usable heart-rate reserve.
        public var fallbackEffort = 1.0
        /// A bout climbing at least this many metres per kilometre gets the elevation multiplier.
        public var hillGainPerKilometer = 50.0
        public var hillMultiplier = 1.3
        /// Dampens the estimated RPE-minute contribution relative to logged training.
        public var weight = 0.25

        public init() {}
    }

    /// Estimate each day's excess against the walking history available before that day.
    public static func walkingLoads(
        _ activity: [DailyActivity], in range: ClosedRange<CalendarDay>, profile: AthleteProfile,
        calendar: Calendar = .current, settings: LoadSettings = LoadSettings()
    ) -> [WalkingLoad] {
        latestPerDay(activity).compactMap { entry in
            guard range.contains(entry.day) else { return nil }
            let usual = baseline(activity, before: entry.day, calendar: calendar)
            let extra = extraWalkingMinutes(entry, baseline: usual)
            guard let baselineMinutes = usual.walkingMinutes, extra > 0 else { return nil }
            let total = entry.walks.reduce(0.0) { load, walk in
                guard walk.durationSeconds.isFinite, walk.durationSeconds > 0 else { return load }
                return load + Workload.sessionRPELoad(rpe: effort(of: walk, profile: profile, settings: settings),
                                               durationMinutes: walk.durationSeconds / 60)
            }
            // Allocate excess minutes proportionally across bouts so the result is independent of their order.
            let load = total * (extra / walkingMinutes(entry)) * settings.weight
            guard load.isFinite, load > 0 else { return nil }
            return WalkingLoad(dailyLoad: DailyLoad(day: entry.day, load: load),
                               extraMinutes: extra, baselineMinutes: baselineMinutes)
        }
    }

    private static func effort(of walk: WalkBout, profile: AthleteProfile, settings: LoadSettings) -> Double {
        if let heartRate = walk.averageHeartRate, let resting = profile.restingHeartRate,
           let maximum = profile.maxHeartRate, resting > 0, resting < maximum,
           (resting...maximum).contains(heartRate), maximum.isFinite {
            // Use heart-rate reserve as a bounded effort proxy in the same units as the other estimates.
            return max(1, min(3, 10 * (heartRate - resting) / (maximum - resting)))
        }
        if let gain = walk.elevationGainMeters, let distance = walk.distanceMeters,
           gain.isFinite, distance.isFinite, distance > 0, gain / (distance / 1_000) >= settings.hillGainPerKilometer {
            return settings.fallbackEffort * settings.hillMultiplier
        }
        return settings.fallbackEffort
    }
}
