import Domain
import Foundation

/// Lower-body strength work today or yesterday, for deciding whether to offer an unplanned run.
/// The defaults are `concurrent-lower-body-run` in the evidence register.
public enum LowerBodyLoad {
    public struct Settings: Sendable {
        /// Lower-body working sets from which yesterday's session counts as heavy.
        public var heavySets = 8
        /// A lower-body set at this RPE or higher makes the session heavy.
        public var heavyRPE = 9.0

        public init() {}
    }

    public enum Level: Hashable, Sendable {
        case none
        /// Lower-body sets today.
        case today
        /// None today, but yesterday's session was heavy.
        case yesterdayHeavy
    }

    public static let evidence = EvidenceReference(key: "concurrent-lower-body-run", level: .heuristic)

    public static func assess(
        sessions: [StrengthSession], exercises: [Exercise], now: Date, calendar: Calendar = .current,
        settings: Settings = .init()
    ) -> Level {
        let lower = Set(exercises.lazy.filter { $0.primaryMuscles.contains { $0.region == .lower } }.map(\.id))
        let today = CalendarDay(now, calendar: calendar)
        let yesterday = today.adding(days: -1, calendar: calendar)
        var level = Level.none
        for session in sessions where session.startedAt <= now {
            let day = CalendarDay(session.startedAt, calendar: calendar)
            guard day == today || day == yesterday else { continue }
            let sets = session.entries.filter { lower.contains($0.exerciseID) }.flatMap(\.sets).filter(\.isWorking)
            guard !sets.isEmpty else { continue }
            if day == today { return .today }
            let hard = sets.count >= settings.heavySets
                || sets.contains { ($0.rpe ?? 0) >= settings.heavyRPE }
            if hard { level = .yesterdayHeavy }
        }
        return level
    }
}
