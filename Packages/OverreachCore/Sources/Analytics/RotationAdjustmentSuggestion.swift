import Domain
import Foundation

/// The decision ladder after a recorded run (ADR-0044, decision 3): keep, swap, postpone or cap the next leg-heavy
/// session. Pure: the caller shows the suggestion and records it only when the athlete accepts.
extension RotationAdjustment {
    public static let evidence = EvidenceReference(key: "rotation-reorder-after-run", level: .heuristic)

    public struct Settings: Sendable {
        /// Days that must separate two heavy-leg sessions (48 h).
        public var minimumHeavyGapDays = 2
        /// A heavy-leg session this many days or fewer before the run counts as fatigue the run adds to.
        public var heavyBeforeRunDays = 2
        /// Days a postponement moves the session.
        public var postponeDays = 1
        /// Top sets of a capped session stop at this RPE.
        public var cappedRPE = 8.0

        public init() {}
    }

    public enum SuggestedAction: Hashable, Sendable {
        /// Light carry-over and green readiness: the plan stands.
        case keep
        /// `heavy` moves to where `lighter` was projected and the other way round.
        case swap(heavy: SessionRotation.Slot, lighter: SessionRotation.Slot)
        case postpone(days: Int)
        /// Same exercises and sets, no load increase, top sets stop at `maxRPE`.
        case keepCapped(maxRPE: Double)
        /// The athlete reported limited movement and neither calendar change fits.
        case holdLegWork
    }

    /// What to do with the next session, and why.
    public struct Suggestion: Hashable, Sendable {
        /// The day the next session is planned for.
        public let day: CalendarDay
        public let action: SuggestedAction
        /// What triggered a change; empty for `keep`.
        public let reasons: [RotationAdjustment.Reason]
        public let evidence: EvidenceReference

        /// A capped session is not read as a stall or a performance drop.
        public var excludedFromProgressionChecks: Bool {
            if case .keepCapped = action { true } else { false }
        }

        /// What to store when the athlete accepts; nothing for a keep or a cap.
        public var adjustment: RotationAdjustment? {
            switch action {
            case let .swap(heavy, lighter):
                RotationAdjustment(day: day, kind: .swap(from: heavy.id, to: lighter.id), reason: reasons.first)
            case let .postpone(days):
                RotationAdjustment(day: day, kind: .postpone(days: days), reason: reasons.first)
            case .keep, .keepCapped, .holdLegWork:
                nil
            }
        }
    }

    /// - Parameters:
    ///   - projection: The detected rotation; without it nothing is suggested.
    ///   - carryover: Level of the recorded run (`RunCarryover`); unknown suggests nothing.
    ///   - readiness: Today's level. Red keeps its own rules and suggests nothing here.
    ///   - previousLegSession: The latest leg session before the run, usually `projection.last`.
    ///   - runDay: The day of the recorded run.
    ///   - recorded: Adjustments already accepted; a session already postponed is not postponed again.
    public static func suggest(
        projection: RotationProjection?, carryover: RunCarryover.Level, readiness: ReadinessLevel,
        previousLegSession: RotationProjection.Session?, runDay: CalendarDay,
        recorded: [RotationAdjustment] = [], legResponse: CheckIn.LegResponse? = nil,
        calendar: Calendar = .current, settings: Settings = .init()
    ) -> Suggestion? {
        let reportsHeavy = legResponse == .heavy
        let reportsLimited = legResponse == .limited
        guard let projection, let next = projection.upcoming.first, readiness != .red, carryover != .unknown,
              next.demand == .heavy || (next.demand == .moderate && (reportsHeavy || reportsLimited))
        else { return nil }

        func suggestion(_ action: SuggestedAction, _ reasons: [Reason] = []) -> Suggestion {
            Suggestion(day: next.day, action: action, reasons: reasons, evidence: evidence)
        }
        if carryover == .light, readiness == .green, !reportsLimited {
            return reportsHeavy ? suggestion(.keepCapped(maxRPE: settings.cappedRPE), [.runCarryover])
                : suggestion(.keep)
        }

        var reasons: [Reason] = []
        if carryover == .notable || reportsLimited || reportsHeavy { reasons.append(.runCarryover) }
        if readiness == .amber { reasons.append(.readiness) }
        if let previous = previousLegSession, previous.demand == .heavy,
           (0...settings.heavyBeforeRunDays).contains(days(from: previous.day, to: runDay, calendar: calendar)) {
            reasons.append(.heavyLegsBeforeRun)
        }
        guard !reasons.isEmpty else { return suggestion(.keep) }

        if let lighter = swapPartner(
            in: projection, avoidLegWork: reportsLimited, settings: settings, calendar: calendar
        ) {
            return suggestion(.swap(heavy: next.slot, lighter: lighter), reasons)
        }
        let alreadyPostponed = recorded.contains {
            guard case let .postpone(days) = $0.kind else { return false }
            let originalDay = projection.last.day.adding(days: projection.cadenceDays, calendar: calendar)
            let shiftedDay = $0.day.adding(days: days, calendar: calendar)
            return $0.day == next.day || ($0.day == originalDay && shiftedDay == next.day)
        }
        if !alreadyPostponed, postponementKeepsHeavyGap(projection, settings: settings, calendar: calendar) {
            return suggestion(.postpone(days: settings.postponeDays), reasons)
        }
        return reportsLimited ? suggestion(.holdLegWork, reasons)
            : suggestion(.keepCapped(maxRPE: settings.cappedRPE), reasons)
    }

    /// The first later slot without leg demand, else with moderate demand, that the heavy slot can trade places with:
    /// every slot stays in the cycle and no two heavy-leg sessions end up closer than the minimum gap.
    private static func swapPartner(
        in projection: RotationProjection, avoidLegWork: Bool, settings: Settings, calendar: Calendar
    ) -> SessionRotation.Slot? {
        let upcoming = projection.upcoming
        let demands: [RotationProjection.Demand] = avoidLegWork ? [.none] : [.none, .moderate]
        for demand in demands {
            for index in upcoming.indices.dropFirst() where upcoming[index].demand == demand {
                // Slots trade places, days stay where they are.
                var sessions = upcoming
                sessions[0] = RotationProjection.Session(
                    day: upcoming[0].day, slot: upcoming[index].slot, demand: upcoming[index].demand)
                sessions[index] = RotationProjection.Session(
                    day: upcoming[index].day, slot: upcoming[0].slot, demand: upcoming[0].demand)
                if heavySessionsKeepGap(
                    previous: projection.last, sessions: sessions, wrap: wrapSession(projection, calendar: calendar),
                    settings: settings, calendar: calendar
                ) { return upcoming[index].slot }
            }
        }
        return nil
    }

    /// Moving every session of the cycle later keeps the gaps among them; only the first heavy-leg session after the
    /// last one gets farther away, so it holds unless the gaps were already too short.
    private static func postponementKeepsHeavyGap(
        _ projection: RotationProjection, settings: Settings, calendar: Calendar
    ) -> Bool {
        let shift = settings.postponeDays
        func later(_ session: RotationProjection.Session) -> RotationProjection.Session {
            RotationProjection.Session(
                day: session.day.adding(days: shift, calendar: calendar), slot: session.slot, demand: session.demand)
        }
        let moved = projection.upcoming.map(later)
        let wrap = wrapSession(projection, calendar: calendar)
        let shiftedWrap = later(wrap)
        return heavySessionsKeepGap(
            previous: projection.last, sessions: moved, wrap: shiftedWrap, settings: settings, calendar: calendar,
            onlyNew: heavyPairs(previous: projection.last, sessions: projection.upcoming, wrap: wrap,
                                settings: settings, calendar: calendar)
        )
    }

    /// The session after the cycle: the first slot again, one cadence after the last projected day.
    private static func wrapSession(
        _ projection: RotationProjection, calendar: Calendar
    ) -> RotationProjection.Session {
        let first = projection.upcoming[0]
        let final = projection.upcoming[projection.upcoming.count - 1]
        return RotationProjection.Session(
            day: final.day.adding(days: projection.cadenceDays, calendar: calendar), slot: first.slot,
            demand: first.demand)
    }

    /// Indexes (in `[previous] + sessions + [wrap]`) of the heavy-leg sessions that follow another closer than
    /// the minimum gap.
    private static func heavyPairs(
        previous: RotationProjection.Session, sessions: [RotationProjection.Session],
        wrap: RotationProjection.Session, settings: Settings, calendar: Calendar
    ) -> Set<String> {
        let all = [previous] + sessions + [wrap]
        let heavy = all.filter { $0.demand == .heavy }
        var close: Set<String> = []
        for (earlier, later) in zip(heavy, heavy.dropFirst())
        where days(from: earlier.day, to: later.day, calendar: calendar) < settings.minimumHeavyGapDays {
            close.insert(earlier.slot.id + ">" + later.slot.id)
        }
        return close
    }

    /// No pair of heavy-leg sessions closer than the minimum gap, other than those already close in `onlyNew`.
    private static func heavySessionsKeepGap(
        previous: RotationProjection.Session, sessions: [RotationProjection.Session],
        wrap: RotationProjection.Session, settings: Settings, calendar: Calendar, onlyNew existing: Set<String> = []
    ) -> Bool {
        let close = heavyPairs(previous: previous, sessions: sessions, wrap: wrap, settings: settings,
                               calendar: calendar)
        return close.isSubset(of: existing)
    }

    private static func days(from start: CalendarDay, to end: CalendarDay, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start.startDate(in: calendar), to: end.startDate(in: calendar)).day ?? 0
    }
}
