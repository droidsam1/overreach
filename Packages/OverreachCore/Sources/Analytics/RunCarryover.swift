import Domain
import Foundation

/// How much a recorded run carries over into the next strength session (ADR-0044, decision 1). *Notable* when the run
/// was hard, long, hilly, unaccustomed, ended soon before the lift, or was followed by soreness or pain that holds.
/// Every threshold is a labelled heuristic in `Settings`. Pure: the caller decides what a notable carry-over changes.
public enum RunCarryover {
    /// The recovery window used when deciding whether to reconsider a lift after a recorded run.
    public static let recentWindow: TimeInterval = 48 * 3_600
    public static let evidence = EvidenceReference(key: "run-before-strength-carryover", level: .limited)

    public enum Level: String, Hashable, Sendable { case light, notable, unknown }

    /// What made the carry-over notable.
    public enum Reason: String, Hashable, Sendable, CaseIterable {
        case hard, long, hilly, unaccustomed, close, soreness, pain
    }

    public struct Settings: Sendable {
        /// Anaerobic training effect at or above this makes a run hard.
        public var hardAnaerobicTrainingEffect = 2.0
        /// Aerobic training effect at or above this makes a run hard.
        public var hardAerobicTrainingEffect = 4.0
        /// A run longer than this is long.
        public var longMinutes = 60.0
        /// A run longer than this share of the longest run of `historyDays` is long.
        public var longestRunFraction = 1.10
        public var historyDays = 30
        /// Descent per kilometre at or above this is hilly. Use ascent when descent is missing.
        public var hillyMetersPerKm = 15.0
        /// No run in this many days before it makes the run unaccustomed (repeated-bout effect).
        public var unaccustomedDays = 14
        /// Fewer hours than this between the end of the run and the next lift is close.
        public var closeHours = 24.0
        /// Check-in soreness (0 none … 3 very sore) at or above this is notable.
        public var soreness = 3
        /// Pain above this severity (0–10) holds even when it settled.
        public var painTolerance = RunPainReport.defaultToleratedSeverity

        public init() {}
    }

    /// The level with the reasons behind it.
    public struct Assessment: Hashable, Sendable {
        public let level: Level
        public let reasons: [Reason]
        /// No training effect, tag or heart rate: intensity was not part of the assessment (Apple Health runs).
        public let intensityUnknown: Bool
    }

    public static func assess(
        run: RunActivity, recentRuns: [RunActivity], checkIn: CheckIn?, nextSessionStart: Date?,
        painReport: RunPainReport? = nil, tag: PlannedRun.Purpose? = nil, settings: Settings = .init()
    ) -> Level {
        assessment(run: run, recentRuns: recentRuns, checkIn: checkIn, nextSessionStart: nextSessionStart,
                   painReport: painReport, tag: tag, settings: settings).level
    }

    public static func assessment(
        run: RunActivity, recentRuns: [RunActivity], checkIn: CheckIn?, nextSessionStart: Date?,
        painReport: RunPainReport? = nil, tag: PlannedRun.Purpose? = nil, settings: Settings = .init()
    ) -> Assessment {
        guard run.durationSeconds.isFinite, run.durationSeconds > 0, run.startedAt.timeIntervalSince1970 > 0 else {
            return Assessment(level: .unknown, reasons: [], intensityUnknown: true)
        }
        let end = run.startedAt.addingTimeInterval(run.durationSeconds)
        let others = RunDeduplication.removingDuplicates(recentRuns).filter {
            // Not the run itself, nor its copy from another source (overlapping time).
            let overlaps = $0.startedAt < end && $0.startedAt.addingTimeInterval($0.durationSeconds) > run.startedAt
            return $0.id != run.id && !overlaps
        }
        var reasons: [Reason] = []

        let effects = [run.anaerobicTrainingEffect.map { $0 >= settings.hardAnaerobicTrainingEffect },
                       run.aerobicTrainingEffect.map { $0 >= settings.hardAerobicTrainingEffect }]
        let taggedHard = tag == .intervals || tag == .race
        if taggedHard || effects.contains(true) { reasons.append(.hard) }
        let intensityUnknown = tag == nil && run.anaerobicTrainingEffect == nil
            && run.aerobicTrainingEffect == nil && run.averageHeartRate == nil

        let windowStart = run.startedAt.addingTimeInterval(-Double(settings.historyDays) * 86_400)
        let window = others.filter { $0.startedAt >= windowStart && $0.startedAt < run.startedAt }
        let longest = SessionCeiling.sessions(window).map(\.distanceMeters).max()
        let overLongest = longest.map { run.distanceMeters > $0 * settings.longestRunFraction } ?? false
        if run.durationSeconds > settings.longMinutes * 60 || overLongest { reasons.append(.long) }

        if let elevation = run.elevationLossMeters ?? run.elevationGainMeters, run.distanceMeters > 0,
           elevation / (run.distanceMeters / 1_000) >= settings.hillyMetersPerKm { reasons.append(.hilly) }

        let accustomedStart = run.startedAt.addingTimeInterval(-Double(settings.unaccustomedDays) * 86_400)
        if !others.contains(where: { $0.startedAt >= accustomedStart && $0.startedAt < run.startedAt }) {
            reasons.append(.unaccustomed)
        }

        if let nextSessionStart, nextSessionStart.timeIntervalSince(end) < settings.closeHours * 3_600 {
            reasons.append(.close)
        }
        if let sore = checkIn?.soreness, sore >= settings.soreness { reasons.append(.soreness) }
        if let painReport, painReport.reportsPain, !painReport.isTolerated(threshold: settings.painTolerance) {
            reasons.append(.pain)
        }
        return Assessment(level: reasons.isEmpty ? .light : .notable, reasons: reasons,
                          intensityUnknown: intensityUnknown)
    }
}
