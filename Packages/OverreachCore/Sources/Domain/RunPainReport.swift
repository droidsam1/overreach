import Foundation

/// The athlete's pain answers for one recorded run, stored by run (activity id + source) so any run can have one,
/// planned or not (#256). Fields are optional so backups written before they existed still decode (ADR-0018).
public struct RunPainReport: Hashable, Codable, Sendable {
    /// Pain-monitoring model: mild pain (up to 5/10) that settles by the next morning is tolerated
    /// (Silbernagel 2007). Overreach's default is the more cautious 3/10, a product choice.
    public static let defaultToleratedSeverity = 3
    public static let scale = 0...10
    public static let keptCount = 60

    public let activityID: String
    public let source: DataSourceKind
    public let startedAt: Date
    public let durationSeconds: Double
    public var painDuring: Bool?
    public var painAfter: Bool?
    public var severityDuring: Int?
    public var severityAfter: Int?
    public var settledByMorning: Bool?

    public init(activityID: String, source: DataSourceKind, startedAt: Date, durationSeconds: Double) {
        self.activityID = activityID
        self.source = source
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
    }

    public init(_ activity: RunActivity) {
        self.init(activityID: activity.id, source: activity.source, startedAt: activity.startedAt,
                  durationSeconds: activity.durationSeconds)
    }

    /// Records a 0–10 answer for each moment; the yes/no fields follow it. Values are clamped to the scale.
    public mutating func answer(during: Int?, after: Int?, settledByMorning settled: Bool?) {
        let clamp = { (value: Int?) in value.map { min(Self.scale.upperBound, max(Self.scale.lowerBound, $0)) } }
        severityDuring = clamp(during)
        severityAfter = clamp(after)
        painDuring = severityDuring.map { $0 > 0 }
        painAfter = severityAfter.map { $0 > 0 }
        settledByMorning = worstSeverity == 0 ? nil : settled
    }

    /// The worst answer given, when a severity was recorded.
    public var worstSeverity: Int? {
        [severityDuring, severityAfter].compactMap { $0 }.max()
    }

    /// Any pain reported, from the severity or the older yes/no answers.
    public var reportsPain: Bool {
        if let worstSeverity { return worstSeverity > 0 }
        return painDuring == true || painAfter == true
    }

    /// Mild pain that settled by morning is tolerated; anything above the threshold, pain that did not settle or has
    /// not been confirmed as settled is not. A yes/no answer without a severity keeps the cautious reading: any pain
    /// is not tolerated.
    public func isTolerated(threshold: Int = defaultToleratedSeverity) -> Bool {
        guard reportsPain else { return true }
        guard let worstSeverity else { return false }
        return worstSeverity <= threshold && settledByMorning == true
    }

    /// The run as an activity without distance, enough to recognise the same run from another source.
    public var asActivity: RunActivity {
        RunActivity(id: activityID, source: source, startedAt: startedAt, durationSeconds: durationSeconds,
                    distanceMeters: 0)
    }

    public func matches(_ activity: RunActivity) -> Bool {
        if activity.source == source { return activity.id == activityID }
        return RunDeduplication.isSameRun(asActivity, activity)
    }

    public func matches(_ other: RunPainReport) -> Bool {
        matches(other.asActivity)
    }
}
