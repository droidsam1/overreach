import Domain
import Foundation
import Testing

@testable import Analytics

@Suite("Keep, swap, postpone or cap the next leg-heavy session")
struct RotationAdjustmentSuggestionTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let sunday = CalendarDay(year: 2026, month: 11, day: 22)
    private func day(_ offset: Int) -> CalendarDay { sunday.adding(days: offset, calendar: calendar) }
    private func slot(_ name: String) -> SessionRotation.Slot { .init(id: name, name: name) }

    private typealias Demand = RotationProjection.Demand

    private func session(_ name: String, _ offset: Int, _ demand: Demand) -> RotationProjection.Session {
        .init(day: day(offset), slot: slot(name), demand: demand)
    }

    /// The first slot (A) was the last session, on Sunday; the next ones follow every `cadence` days, A again last.
    private func projection(
        _ demands: [Demand] = [.heavy, .heavy, .none, .none], cadence: Int = 2
    ) -> RotationProjection {
        let names = Array(["A", "B", "C", "D"].prefix(demands.count))
        let upcoming = (1...demands.count).map { step in
            session(names[step % names.count], cadence * step, demands[step % names.count])
        }
        return RotationProjection(cadenceDays: cadence, last: session(names[0], 0, demands[0]), upcoming: upcoming)
    }

    private func suggest(
        _ projection: RotationProjection?, _ carryover: RunCarryover.Level, _ readiness: ReadinessLevel = .green,
        recorded: [RotationAdjustment] = []
    ) -> RotationAdjustment.Suggestion? {
        RotationAdjustment.suggest(
            projection: projection, carryover: carryover, readiness: readiness,
            previousLegSession: projection?.last, runDay: day(1), recorded: recorded, calendar: calendar)
    }

    @Test func anEasyRunWithGreenReadinessKeepsTheHeavyDay() throws {
        let result = try #require(suggest(projection(), .light))
        #expect(result.action == .keep)
        #expect(result.reasons.isEmpty)
        #expect(result.adjustment == nil)
        #expect(result.evidence.key == "rotation-reorder-after-run")
    }

    @Test func aNotableRunSwapsTheHeavySlotWithTheFirstLaterSlotWithoutLegDemand() throws {
        let result = try #require(suggest(projection([.heavy, .heavy, .moderate, .none]), .notable))
        // D has no leg demand: it is preferred to C, which has moderate demand.
        #expect(result.action == .swap(heavy: slot("B"), lighter: slot("D")))
        #expect(result.reasons == [.runCarryover, .heavyLegsBeforeRun])
        #expect(result.day == day(2))
        #expect(result.adjustment == RotationAdjustment(
            day: day(2), kind: .swap(from: "B", to: "D"), reason: .runCarryover))
    }

    @Test func aModerateSlotIsUsedWhenNoSlotHasNoLegDemand() throws {
        let result = try #require(suggest(projection([.heavy, .heavy, .moderate, .moderate]), .notable))
        #expect(result.action == .swap(heavy: slot("B"), lighter: slot("C")))
    }

    @Test func amberReadinessWithAnEasyRunSwaps() throws {
        let result = try #require(suggest(projection(), .light, .amber))
        #expect(result.action == .swap(heavy: slot("B"), lighter: slot("C")))
        #expect(result.reasons.contains(.readiness))
    }

    @Test func aHeavyLegSessionJustBeforeAnEasyRunSwapsWhenReadinessIsUnknown() throws {
        let result = try #require(suggest(projection(), .light, .unknown))
        #expect(result.action == .swap(heavy: slot("B"), lighter: slot("C")))
        #expect(result.reasons == [.heavyLegsBeforeRun])
    }

    @Test func aSwapNeverPutsTwoHeavyLegSessionsWithin48Hours() throws {
        // One session a day: B (heavy) next to C (none) and D (heavy). Moving B after C would sit it beside D.
        let plan = projection([.heavy, .heavy, .none, .heavy], cadence: 1)
        let result = try #require(suggest(plan, .notable))
        if case .swap = result.action { Issue.record("a swap must not create heavy sessions less than 48 h apart") }
    }

    @Test func aSwapKeepsEverySlotInTheCycle() throws {
        let plan = projection([.heavy, .heavy, .none, .moderate])
        let result = try #require(suggest(plan, .notable))
        guard case let .swap(heavy, lighter) = result.action else {
            Issue.record("expected a swap")
            return
        }
        #expect(plan.upcoming.contains { $0.slot == heavy } && plan.upcoming.contains { $0.slot == lighter })
        #expect(heavy != lighter)
    }

    @Test func withoutALighterSlotTheSessionIsPostponedOneDay() throws {
        let result = try #require(suggest(projection([.heavy, .heavy]), .notable))
        #expect(result.action == .postpone(days: 1))
        #expect(result.adjustment == RotationAdjustment(
            day: day(2), kind: .postpone(days: 1), reason: .runCarryover))
    }

    @Test func aSessionAlreadyPostponedIsKeptCapped() throws {
        let recorded = [RotationAdjustment(day: day(2), kind: .postpone(days: 1))]
        let result = try #require(suggest(projection([.heavy, .heavy]), .notable, recorded: recorded))
        #expect(result.action == .keepCapped(maxRPE: 8))
        #expect(result.excludedFromProgressionChecks)
        #expect(result.adjustment == nil)
    }

    @Test func anUpperBodyNextSlotNeedsNothing() {
        #expect(suggest(projection([.heavy, .none, .heavy, .none]), .notable) == nil)
        #expect(suggest(projection([.heavy, .moderate, .heavy, .none]), .notable) == nil)
    }

    @Test func noProjectionRedReadinessOrUnknownCarryoverSuggestNothing() {
        #expect(suggest(nil, .notable) == nil)
        #expect(suggest(projection(), .notable, .red) == nil)
        #expect(suggest(projection(), .unknown) == nil)
    }
}
