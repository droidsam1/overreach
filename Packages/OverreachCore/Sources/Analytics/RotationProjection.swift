import Domain
import Foundation

/// The detected strength rotation laid onto the calendar, and how well each rest day suits a run.
///
/// Someone who repeats A, B, C, D on alternate days without dated plans still lifts on a known day: the rotation
/// says which workout comes next and the recent gaps say when. The projection only exists when both are stable,
/// otherwise nothing is guessed. The scoring defaults are `concurrent-lower-body-run` in the evidence register.
public struct RotationProjection: Hashable, Sendable {
    /// How hard a workout works the legs, read from its last completed session.
    public enum Demand: Hashable, Sendable {
        case heavy
        case moderate
        case none
    }

    public struct Session: Hashable, Sendable {
        public let day: CalendarDay
        public let slot: SessionRotation.Slot
        public let demand: Demand

        public init(day: CalendarDay, slot: SessionRotation.Slot, demand: Demand) {
            self.day = day
            self.slot = slot
            self.demand = demand
        }
    }

    public struct Settings: Sendable {
        public var lowerBody = LowerBodyLoad.Settings()
        /// A lower-body working set of this many reps or fewer counts as a heavy, low-rep set.
        public var lowRepMaximum = 5
        /// Low-rep lower-body working sets from which a session counts as heavy.
        public var lowRepSets = 3
        /// Longest usual gap between sessions that is still projected.
        public var longestCadenceDays = 4

        public init() {}
    }

    public static let evidence = LowerBodyLoad.evidence

    /// Days between sessions, e.g. 2 for alternate days.
    public let cadenceDays: Int
    /// The last session recorded, the reference for the first projected one.
    public let last: Session
    /// One full cycle of projected sessions after `last`, in order.
    public let upcoming: [Session]

    /// - Parameters:
    ///   - sessions: Logged strength sessions, in any order.
    ///   - exercises: The catalog, for telling lower-body exercises apart.
    ///   - adjustments: Swaps and postponements the athlete accepted (ADR-0044). A recorded postponement shifts the
    ///     projection instead of breaking it; after a swapped pair the original order resumes. Without a record, any
    ///     change of order or rhythm drops the projection as before.
    public static func project(
        sessions: [StrengthSession], exercises: [Exercise], now: Date, calendar: Calendar = .current,
        adjustments: [RotationAdjustment] = [], settings: Settings = .init()
    ) -> RotationProjection? {
        let done = sessions.filter { $0.startedAt <= now }
        guard let rotation = SessionRotation.detect(in: done, adjustments: adjustments, calendar: calendar)
        else { return nil }
        let timeline = SessionRotation.timeline(done)
        let days = timeline.map { CalendarDay($0.session.startedAt, calendar: calendar) }
        // Every gap between the sessions that proved the rotation must match.
        let proving = Array(days.suffix(rotation.order.count * SessionRotation.requiredCycles))
        guard proving.count >= 2 else { return nil }
        let postponements = adjustments.compactMap { adjustment -> (actual: CalendarDay, days: Int)? in
            guard case let .postpone(days) = adjustment.kind, days > 0 else { return nil }
            return (adjustment.day.adding(days: days, calendar: calendar), days)
        }
        // A recorded postponement is not a break in the rhythm: the session it moved ran that many days late.
        let gaps = zip(proving, proving.dropFirst()).map { earlier, later in
            let raw = calendar.dateComponents(
                [.day], from: earlier.startDate(in: calendar), to: later.startDate(in: calendar)
            ).day ?? 0
            return raw - (postponements.first { $0.actual == later }?.days ?? 0)
        }
        guard let cadence = gaps.first, (1...settings.longestCadenceDays).contains(cadence),
              gaps.allSatisfy({ $0 == cadence }), let latest = timeline.last else { return nil }

        let lower = Set(exercises.lazy.filter { $0.primaryMuscles.contains { $0.region == .lower } }.map(\.id))
        let demand: (SessionRotation.Slot) -> Demand = { slot in
            timeline.last { $0.slot.id == slot.id }.map { classify($0.session, lower: lower, settings: settings) }
                ?? .none
        }
        let lastDay = days[days.count - 1]
        // A postponement accepted for the next session shifts every projected session.
        let nextPlanned = lastDay.adding(days: cadence, calendar: calendar)
        let shift = adjustments.compactMap { adjustment -> Int? in
            guard case let .postpone(days) = adjustment.kind, days > 0, adjustment.day == nextPlanned else { return nil }
            return days
        }.first ?? 0
        let upcoming = rotation.order.enumerated().map { index, slot in
            let slot = index == 0 ? rotation.next : slot
            return Session(day: lastDay.adding(days: cadence * (index + 1) + shift, calendar: calendar), slot: slot,
                           demand: demand(slot))
        }
        // A missed session breaks the rhythm: do not guess where it went.
        let today = CalendarDay(now, calendar: calendar)
        guard let next = upcoming.first, next.day >= today else { return nil }
        return RotationProjection(
            cadenceDays: cadence, last: Session(day: lastDay, slot: latest.slot, demand: demand(latest.slot)),
            upcoming: upcoming
        )
    }

    /// The projected session on `day`, if any.
    public func session(on day: CalendarDay) -> Session? {
        upcoming.first { $0.day == day }
    }

    /// Rest days from `today` through the end of the projected cycle, each scored as a window for a run. The
    /// session after the cycle is the first one again (day 9 of an 8-day cycle is A).
    public func runWindows(from today: CalendarDay, calendar: Calendar = .current) -> [RunWindow] {
        guard let first = upcoming.first, let final = upcoming.last else { return [] }
        let end = final.day.adding(days: cadenceDays, calendar: calendar)
        let sessions = [last] + upcoming + [Session(day: end, slot: first.slot, demand: first.demand)]
        var day = max(today, last.day.adding(days: 1, calendar: calendar))
        var windows: [RunWindow] = []
        while day < end {
            defer { day = day.adding(days: 1, calendar: calendar) }
            guard !sessions.contains(where: { $0.day == day }) else { continue }
            let before = sessions.first { $0.day == day.adding(days: -1, calendar: calendar) }
            let after = sessions.first { $0.day == day.adding(days: 1, calendar: calendar) }
            windows.append(Self.window(day: day, before: before, after: after))
        }
        return windows
    }

    private static func window(day: CalendarDay, before: Session?, after: Session?) -> RunWindow {
        if let before, before.demand == .heavy {
            return RunWindow(day: day, quality: .avoid, reason: .afterHeavyLower(before.slot))
        }
        if let after, after.demand == .heavy {
            return RunWindow(day: day, quality: .good, reason: .beforeHeavyLower(after.slot))
        }
        if let before, before.demand == .moderate {
            return RunWindow(day: day, quality: .good, reason: .afterModerateLower(before.slot))
        }
        return RunWindow(day: day, quality: .best, reason: .awayFromLowerBody)
    }

    static func classify(_ session: StrengthSession, lower: Set<UUID>, settings: Settings) -> Demand {
        let sets = session.entries.filter { lower.contains($0.exerciseID) }.flatMap(\.sets).filter(\.isWorking)
        guard !sets.isEmpty else { return .none }
        let lowRep = sets.filter { set in
            set.reps.map { (1...settings.lowRepMaximum).contains($0) } == true && (set.weightKg ?? 0) > 0
        }
        let heavy = sets.count >= settings.lowerBody.heavySets
            || sets.contains { ($0.rpe ?? 0) >= settings.lowerBody.heavyRPE }
            || lowRep.count >= settings.lowRepSets
        return heavy ? .heavy : .moderate
    }
}

/// A rest day of the projected rotation, scored as a day for a run.
public struct RunWindow: Hashable, Sendable {
    public enum Quality: Hashable, Sendable {
        case best
        /// Fine, but a leg-heavy session sits on one side.
        case good
        case avoid
    }

    /// The neighbour that decided the quality.
    public enum Reason: Hashable, Sendable {
        case afterHeavyLower(SessionRotation.Slot)
        case beforeHeavyLower(SessionRotation.Slot)
        case afterModerateLower(SessionRotation.Slot)
        /// No leg-heavy workout on the day before or after.
        case awayFromLowerBody
    }

    public let day: CalendarDay
    public let quality: Quality
    public let reason: Reason

    public init(day: CalendarDay, quality: Quality, reason: Reason) {
        self.day = day
        self.quality = quality
        self.reason = reason
    }
}
