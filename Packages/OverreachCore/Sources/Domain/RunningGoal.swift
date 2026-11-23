import Foundation

/// The run the athlete wants to achieve. Target pace is a goal, independent of current training pace.
public struct RunningGoal: Hashable, Codable, Sendable {
    public let distanceMeters: Int
    public let targetSeconds: Int?
    public let aimsForPainFree: Bool

    public init(distanceMeters: Int, targetSeconds: Int? = nil, aimsForPainFree: Bool = false) {
        self.distanceMeters = distanceMeters
        self.targetSeconds = targetSeconds
        self.aimsForPainFree = aimsForPainFree
    }

    public var targetPaceSecondsPerKm: Double? {
        guard distanceMeters > 0, let targetSeconds, targetSeconds > 0 else { return nil }
        return 1_000 * Double(targetSeconds) / Double(distanceMeters)
    }

    /// One confirmed recording must establish every selected criterion. Whole-run time is an upper bound
    /// on the time to cover the goal distance. Split times can establish additional results when available.
    public func isMet(by result: PlannedRunCompletion) -> Bool {
        guard distanceMeters > 0, let measured = result.distanceMeters, measured.isFinite,
              measured >= Double(distanceMeters) else { return false }
        if let targetSeconds {
            guard targetSeconds > 0, result.durationSeconds.isFinite, result.durationSeconds > 0,
                  result.durationSeconds <= Double(targetSeconds) else { return false }
        }
        return !aimsForPainFree || (result.painDuring == false && result.painAfter == false)
    }
}

/// A dated entry entered by the athlete. It remains separate from recorded run history.
public struct PlannedRun: Identifiable, Hashable, Codable, Sendable {
    public enum Purpose: String, CaseIterable, Codable, Sendable {
        case easy, intervals, tempo, threshold, long, race, rest
    }

    public enum RacePriority: String, CaseIterable, Codable, Sendable { case primary, secondary }

    public enum IntensityBasis: String, CaseIterable, Codable, Sendable { case pace, heartRateZone, perceivedEffort }

    public struct Prescription: Hashable, Codable, Sendable {
        public let repetitions: Int?
        public let recoverySeconds: Int?
        public let intensityBasis: IntensityBasis?
        public let intensityTarget: Int?

        public init(
            repetitions: Int? = nil, recoverySeconds: Int? = nil,
            intensityBasis: IntensityBasis? = nil, intensityTarget: Int? = nil
        ) {
            self.repetitions = repetitions
            self.recoverySeconds = repetitions == nil ? nil : recoverySeconds
            self.intensityBasis = intensityBasis
            self.intensityTarget = intensityBasis == nil ? nil : intensityTarget
        }
    }

    public let id: UUID
    public let day: CalendarDay
    public let purpose: Purpose
    public let durationMinutes: Int?
    public let distanceMeters: Int?
    public let prescription: Prescription?
    public let racePriority: RacePriority?
    public let originalDay: CalendarDay?
    public let postponed: Bool?
    public var isPostponed: Bool { postponed == true }
    public var isAdjusted: Bool { originalDay != nil && originalDay != day }
    public private(set) var completion: PlannedRunCompletion?

    public init(
        id: UUID = UUID(), day: CalendarDay, purpose: Purpose, durationMinutes: Int? = nil, distanceMeters: Int? = nil,
        completion: PlannedRunCompletion? = nil, prescription: Prescription? = nil,
        racePriority: RacePriority? = nil, originalDay: CalendarDay? = nil, postponed: Bool = false
    ) {
        self.id = id
        self.day = day
        self.purpose = purpose
        self.durationMinutes = purpose == .rest ? nil : durationMinutes
        self.distanceMeters = purpose == .rest ? nil : distanceMeters
        self.completion = purpose == .rest ? nil : completion
        self.prescription = purpose == .rest ? nil : prescription
        self.racePriority = purpose == .race ? racePriority : nil
        self.originalDay = originalDay
        self.postponed = postponed && purpose != .rest && completion == nil ? true : nil
    }

    public func updatingCompletion(_ completion: PlannedRunCompletion) -> Self {
        var updated = self
        if purpose != .rest && !isPostponed { updated.completion = completion }
        return updated
    }

    /// The same entry as a shorter easy run: identity, day and first date stay; distance, structure and race
    /// priority go. An entry that is rest, a race, postponed or already completed is returned unchanged.
    public func easingTo(minutes: Int) -> Self {
        guard minutes > 0, purpose != .rest, purpose != .race, !isPostponed, completion == nil else { return self }
        return Self(id: id, day: day, purpose: .easy, durationMinutes: minutes, originalDay: originalDay)
    }

    private enum CodingKeys: String, CodingKey {
        case id, day, purpose, durationMinutes, distanceMeters, completion
        case prescription, racePriority, originalDay, postponed
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let day = try values.decode(CalendarDay.self, forKey: .day)
        let purpose = try values.decode(Purpose.self, forKey: .purpose)
        let minutes = try values.decodeIfPresent(Int.self, forKey: .durationMinutes)
        let distance = try values.decodeIfPresent(Int.self, forKey: .distanceMeters)
        let id = try values.decodeIfPresent(UUID.self, forKey: .id)
            ?? UUID.stable("planned-run/\(day)/\(purpose.rawValue)/\(minutes ?? 0)")
        self.init(id: id, day: day, purpose: purpose, durationMinutes: minutes, distanceMeters: distance,
                  completion: try values.decodeIfPresent(PlannedRunCompletion.self, forKey: .completion),
                  prescription: try values.decodeIfPresent(Prescription.self, forKey: .prescription),
                  racePriority: try values.decodeIfPresent(RacePriority.self, forKey: .racePriority),
                  originalDay: try values.decodeIfPresent(CalendarDay.self, forKey: .originalDay),
                  postponed: try values.decodeIfPresent(Bool.self, forKey: .postponed) ?? false)
    }
}

/// An explicit user confirmation. Keep just enough data to recognize a mirrored recording later.
public struct PlannedRunCompletion: Hashable, Codable, Sendable {
    public let activityID: String
    public let source: DataSourceKind
    public let startedAt: Date
    public let durationSeconds: Double
    public let distanceMeters: Double?
    public var painDuring: Bool?
    public var painAfter: Bool?
    /// Worst pain during and after the run, 0–10 (#256). Absent on runs answered with yes or no only.
    public var severityDuring: Int?
    public var severityAfter: Int?
    /// Whether the pain was gone by the next morning. Absent until the athlete answers.
    public var settledByMorning: Bool?

    public init(_ activity: RunActivity) {
        activityID = activity.id
        source = activity.source
        startedAt = activity.startedAt
        durationSeconds = activity.durationSeconds
        distanceMeters = activity.distanceMeters.isFinite && activity.distanceMeters > 0 ? activity.distanceMeters : nil
    }

    public func matches(_ activity: RunActivity) -> Bool {
        if activity.source == source { return activity.id == activityID }
        let reference = RunActivity(id: activityID, source: source, startedAt: startedAt,
                                    durationSeconds: durationSeconds, distanceMeters: 0)
        return RunDeduplication.isSameRun(reference, activity)
    }

    /// The pain answers of this run, in the shape shared with runs that have no planned entry.
    public var painReport: RunPainReport {
        var report = RunPainReport(activityID: activityID, source: source, startedAt: startedAt,
                                   durationSeconds: durationSeconds)
        report.painDuring = painDuring
        report.painAfter = painAfter
        report.severityDuring = severityDuring
        report.severityAfter = severityAfter
        report.settledByMorning = settledByMorning
        return report
    }

    public func matches(_ other: PlannedRunCompletion) -> Bool {
        matches(RunActivity(id: other.activityID, source: other.source, startedAt: other.startedAt,
                            durationSeconds: other.durationSeconds, distanceMeters: 0))
    }
}
