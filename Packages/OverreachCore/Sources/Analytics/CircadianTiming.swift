import Domain
import Foundation

/// Evidence behind the timing insights (ADR-0045, `docs/evidence.md` → Circadian timing).
public enum CircadianEvidence {
    /// Irregular sleep timing (Sleep Regularity Index) predicts mortality independently of duration
    /// (Windred et al. 2024, observational).
    public static let sleepRegularity = EvidenceReference(key: "sleep-regularity", level: .limited)
    /// Weekend-vs-weekday shift of the sleep midpoint: small observational associations (social jetlag).
    public static let socialJetlag = EvidenceReference(key: "social-jetlag", level: .limited)
    /// Hard exercise ending ≤ 1 h before bed can delay sleep; ending ≥ 2 h before is neutral or helpful.
    public static let eveningExercise = EvidenceReference(key: "evening-exercise-sleep", level: .moderate)
    /// A steady training time goes with more exercise (observational); no benefit of the hour itself is shown.
    public static let trainingTimeConsistency = EvidenceReference(key: "training-time-consistency", level: .limited)
}

/// Looks at when the athlete sleeps and trains and says what the evidence supports about it (ADR-0045).
/// Pure and deterministic. Not a diagnosis: timing statistics are associations, not causes.
public enum CircadianTiming {
    /// A night or a session reduced to the instants this analysis needs.
    public struct Span: Hashable, Sendable {
        public var start: Date
        public var end: Date
        /// Only meaningful for sessions: the athlete rated it hard (RPE ≥ 8), or it was an interval or race day.
        public var isHard: Bool

        public init(start: Date, end: Date, isHard: Bool = false) {
            self.start = start
            self.end = end
            self.isHard = isHard
        }
    }

    public struct Settings: Hashable, Sendable {
        public var minimumNights = 7
        public var minimumSessions = 5
        /// Sleep Regularity Index below which sleep is flagged as irregular. Heuristic: the UK Biobank median was 81
        /// (IQR 73.8–86.3), so below 70 is roughly the least regular fifth (Windred et al. 2024).
        public var irregularRegularityIndex = 70.0
        /// Pairs of consecutive nights the index needs; with fewer, the midpoint spread decides.
        public var minimumRegularityPairs = 5
        /// Sleep-midpoint spread (circular SD) above which sleep is flagged when the index is unavailable. Heuristic.
        public var irregularMidpointMinutes = 60.0
        /// Weekend-vs-weekday midpoint shift above which it is mentioned. Heuristic.
        public var socialJetlagMinutes = 60.0
        /// Start-time spread above which training time is called variable. Heuristic.
        public var variableTrainingMinutes = 120.0
        /// A hard session ending less than this long before the usual bedtime is flagged (≤ 1 h in the reviews).
        public var hardSessionBufferMinutes = 60.0
        /// Share of hard sessions that must be close to bed before it counts as a pattern.
        public var lateHardShare = 0.25

        public init() {}
    }

    public struct Report: Hashable, Sendable {
        /// Clock times are minutes after local midnight, 0..<1,440.
        public var nights: Int
        public var usualBedtime: Double?
        public var usualWake: Double?
        public var bedtimeSpread: Double?
        public var wakeSpread: Double?
        /// Circular SD of the sleep midpoint: moves with both bedtime and wake time.
        public var midpointSpread: Double?
        /// Sleep Regularity Index, −100...100: 100 = asleep and awake at the same clock minutes on consecutive days.
        /// Built from main sleep spans only (naps and night wakings are not seen), so it reads higher than actigraphy.
        public var regularityIndex: Double?
        /// Weekend midpoint minus weekday midpoint, in minutes. Positive = later on weekends.
        public var weekendShift: Double?
        public var sessions: Int
        public var usualTrainingStart: Double?
        public var trainingSpread: Double?
        public var hardSessions: Int
        public var hardSessionsNearBed: Int
        public var insights: [Insight]

        public init(
            nights: Int = 0, usualBedtime: Double? = nil, usualWake: Double? = nil, bedtimeSpread: Double? = nil,
            wakeSpread: Double? = nil, midpointSpread: Double? = nil, regularityIndex: Double? = nil,
            weekendShift: Double? = nil, sessions: Int = 0, usualTrainingStart: Double? = nil,
            trainingSpread: Double? = nil, hardSessions: Int = 0, hardSessionsNearBed: Int = 0,
            insights: [Insight] = []
        ) {
            self.nights = nights
            self.usualBedtime = usualBedtime
            self.usualWake = usualWake
            self.bedtimeSpread = bedtimeSpread
            self.wakeSpread = wakeSpread
            self.midpointSpread = midpointSpread
            self.regularityIndex = regularityIndex
            self.weekendShift = weekendShift
            self.sessions = sessions
            self.usualTrainingStart = usualTrainingStart
            self.trainingSpread = trainingSpread
            self.hardSessions = hardSessions
            self.hardSessionsNearBed = hardSessionsNearBed
            self.insights = insights
        }
    }

    public enum Insight: Hashable, Sendable {
        /// `regularityIndex` is nil when too few consecutive nights exist and the midpoint spread decided.
        case irregularSleep(regularityIndex: Int?, midpointSpreadMinutes: Int)
        case socialJetlag(minutes: Int)
        case variableTrainingTime(spreadMinutes: Int)
        case hardSessionsNearBed(count: Int, total: Int)

        public var evidence: EvidenceReference {
            switch self {
            case .irregularSleep: CircadianEvidence.sleepRegularity
            case .socialJetlag: CircadianEvidence.socialJetlag
            case .variableTrainingTime: CircadianEvidence.trainingTimeConsistency
            case .hardSessionsNearBed: CircadianEvidence.eveningExercise
            }
        }
    }

    public static func analyze(
        nights: [Span], sessions: [Span], calendar: Calendar = .current, settings: Settings = Settings()
    ) -> Report {
        let valid = nights.filter { $0.start < $0.end }
        let bedtimes = valid.map { minuteOfDay($0.start, calendar: calendar) }
        let wakes = valid.map { minuteOfDay($0.end, calendar: calendar) }
        let enough = valid.count >= settings.minimumNights

        let bedtime = enough ? circularMean(bedtimes) : nil
        let bedSpread = enough ? circularSpread(bedtimes) : nil
        let midSpread = enough ? circularSpread(valid.map { midpoint($0, calendar: calendar) }) : nil
        let regularity =
            enough ? regularityIndex(valid, calendar: calendar, minimumPairs: settings.minimumRegularityPairs) : nil
        let shift = enough ? weekendShift(valid, calendar: calendar) : nil

        let timed = sessions.filter { $0.start < $0.end }
        let starts = timed.map { minuteOfDay($0.start, calendar: calendar) }
        let enoughSessions = timed.count >= settings.minimumSessions
        let trainingSpread = enoughSessions ? circularSpread(starts) : nil

        let hard = timed.filter(\.isHard)
        let near = bedtime.map { usual in
            hard.filter {
                isNearBed($0, usualBedtime: usual, calendar: calendar, buffer: settings.hardSessionBufferMinutes)
            }.count
        } ?? 0

        var insights: [Insight] = []
        if let midSpread {
            let irregular =
                regularity.map { $0 < settings.irregularRegularityIndex }
                ?? (midSpread > settings.irregularMidpointMinutes)
            if irregular {
                insights.append(
                    .irregularSleep(
                        regularityIndex: regularity.map { Int($0.rounded()) },
                        midpointSpreadMinutes: Int(midSpread.rounded())))
            }
        }
        if let shift, shift > settings.socialJetlagMinutes {
            insights.append(.socialJetlag(minutes: Int(shift.rounded())))
        }
        if let trainingSpread, trainingSpread > settings.variableTrainingMinutes {
            insights.append(.variableTrainingTime(spreadMinutes: Int(trainingSpread.rounded())))
        }
        if hard.count >= 3, bedtime != nil, Double(near) / Double(hard.count) >= settings.lateHardShare {
            insights.append(.hardSessionsNearBed(count: near, total: hard.count))
        }

        return Report(
            nights: valid.count, usualBedtime: bedtime, usualWake: enough ? circularMean(wakes) : nil,
            bedtimeSpread: bedSpread, wakeSpread: enough ? circularSpread(wakes) : nil, midpointSpread: midSpread,
            regularityIndex: regularity, weekendShift: shift,
            sessions: timed.count, usualTrainingStart: enoughSessions ? circularMean(starts) : nil,
            trainingSpread: trainingSpread, hardSessions: hard.count, hardSessionsNearBed: near, insights: insights)
    }

    // MARK: Clock helpers (circular, so 23:50 and 00:10 are 20 minutes apart)

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    static func circularMean(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        let angles = minutes.map { $0 / 1440 * 2 * .pi }
        let sine = angles.map(sin).reduce(0, +)
        let cosine = angles.map(cos).reduce(0, +)
        var mean = atan2(sine, cosine) / (2 * .pi) * 1440
        if mean < 0 { mean += 1440 }
        return mean
    }

    /// Circular standard deviation in minutes: `sqrt(-2 ln R)` with R the mean resultant length.
    static func circularSpread(_ minutes: [Double]) -> Double? {
        guard minutes.count > 1 else { return nil }
        let angles = minutes.map { $0 / 1440 * 2 * .pi }
        let sine = angles.map(sin).reduce(0, +) / Double(angles.count)
        let cosine = angles.map(cos).reduce(0, +) / Double(angles.count)
        let resultant = min(1, max(1e-9, (sine * sine + cosine * cosine).squareRoot()))
        return (-2 * log(resultant)).squareRoot() / (2 * .pi) * 1440
    }

    static func midpoint(_ span: Span, calendar: Calendar) -> Double {
        minuteOfDay(span.start.addingTimeInterval(span.end.timeIntervalSince(span.start) / 2), calendar: calendar)
    }

    /// Sleep Regularity Index (Phillips et al. 2017) from one main sleep per day: each night is placed in the 24 h
    /// window from noon before its wake day, and nights on consecutive wake days are compared minute by minute.
    /// SRI = 200 × (share of minutes in the same state) − 100. Nil with fewer than `minimumPairs` consecutive pairs.
    static func regularityIndex(_ nights: [Span], calendar: Calendar, minimumPairs: Int) -> Double? {
        var byDay: [Date: (start: Double, end: Double)] = [:]
        for night in nights {
            let day = calendar.startOfDay(for: night.end)
            guard let anchor = calendar.date(byAdding: .hour, value: -12, to: day) else { continue }
            let start = max(0, min(1440, night.start.timeIntervalSince(anchor) / 60))
            let end = max(0, min(1440, night.end.timeIntervalSince(anchor) / 60))
            if let kept = byDay[day], kept.end - kept.start >= end - start { continue }
            byDay[day] = (start, end)
        }
        var agreements: [Double] = []
        for (day, first) in byDay {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), let second = byDay[next] else {
                continue
            }
            let overlap = max(0, min(first.end, second.end) - max(first.start, second.start))
            let differing = (first.end - first.start) + (second.end - second.start) - 2 * overlap
            agreements.append(1 - differing / 1440)
        }
        guard agreements.count >= minimumPairs else { return nil }
        return 200 * agreements.reduce(0, +) / Double(agreements.count) - 100
    }

    /// Mean midpoint of nights waking on Saturday/Sunday minus the rest. Free days stand in for the unknown work
    /// schedule, so this misreads shift workers.
    private static func weekendShift(_ nights: [Span], calendar: Calendar) -> Double? {
        func isFree(_ span: Span) -> Bool { [1, 7].contains(calendar.component(.weekday, from: span.end)) }
        let free = nights.filter(isFree)
        let work = nights.filter { !isFree($0) }
        guard free.count >= 2, work.count >= 3,
            let freeMid = circularMean(free.map { midpoint($0, calendar: calendar) }),
            let workMid = circularMean(work.map { midpoint($0, calendar: calendar) })
        else { return nil }
        var diff = freeMid - workMid
        if diff > 720 { diff -= 1440 }
        if diff < -720 { diff += 1440 }
        return diff
    }

    private static func isNearBed(_ session: Span, usualBedtime: Double, calendar: Calendar, buffer: Double) -> Bool {
        var gap = usualBedtime - minuteOfDay(session.end, calendar: calendar)
        if gap < -720 { gap += 1440 }
        if gap > 720 { gap -= 1440 }
        return gap >= 0 && gap < buffer
    }
}
