import Domain
import Foundation
import Testing

@Suite("AthleteProfile")
struct AthleteProfileTests {
    @Test func defaultsAreNeutral() {
        let profile = AthleteProfile()
        #expect(profile.sex == nil)
        #expect(profile.cycleTracking == .off)
        #expect(!profile.usesCyclePhase)
        #expect(!profile.walkingRoutine.hasDog)
    }

    @Test func onlyNaturalCycleEstimatesPhase() {
        #expect(CycleTrackingMode.naturalCycle.estimatesPhase)
        #expect(!CycleTrackingMode.hormonalContraception.estimatesPhase)
        #expect(!CycleTrackingMode.menopause.estimatesPhase)
        #expect(!CycleTrackingMode.off.estimatesPhase)
    }

    @Test func roundTripsThroughJSON() throws {
        let profile = AthleteProfile(
            sex: .female,
            birthYear: 1992,
            bodyMassKg: 61.5,
            cycleTracking: .naturalCycle,
            walkingRoutine: WalkingRoutine(hasDog: true, usualWalksPerDay: 3, walksAreFixed: true, canRunDuringWalks: true)
        )
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(AthleteProfile.self, from: data) == profile)
    }
}

@Suite("Cycle and activity context")
struct ContextTypesTests {
    @Test func symptomsMaxSeverityIgnoresMissingValues() {
        #expect(CycleSymptoms().maxSeverity == nil)
        #expect(CycleSymptoms(cramps: 2, headache: 1).maxSeverity == 2)
    }

    @Test func walkingSecondsSumsAllWalks() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let activity = DailyActivity(
            day: CalendarDay(year: 2026, month: 11, day: 16),
            steps: 14_200,
            walks: [
                WalkBout(start: start, durationSeconds: 1_800, source: .appleHealth),
                WalkBout(start: start.addingTimeInterval(7_200), durationSeconds: 2_700, source: .garmin),
            ]
        )
        #expect(activity.walkingSeconds == 4_500)
        #expect(activity.walks[0].end == start.addingTimeInterval(1_800))
    }

    @Test func evidenceLevelsAreOrdered() {
        #expect(EvidenceLevel.heuristic < .limited)
        #expect(EvidenceLevel.limited < .moderate)
        #expect(EvidenceLevel.moderate < .strong)
    }
}

@Suite("Profile wearables")
struct ProfileWearablesTests {
    @Test func olderProfilesHaveNoWatchesAndUnknownOnesAreDropped() throws {
        let old = try JSONDecoder().decode(AthleteProfile.self, from: Data(#"{"cycleTracking":"off"}"#.utf8))
        #expect(old.wearables.isEmpty)

        let newer = try JSONDecoder().decode(
            AthleteProfile.self, from: Data(#"{"wearables":["garmin","smartRing"]}"#.utf8)
        )
        #expect(newer.wearables == [.garmin])

        let roundTrip = try JSONDecoder().decode(
            AthleteProfile.self, from: JSONEncoder().encode(AthleteProfile(wearables: [.appleWatch, .garmin]))
        )
        #expect(roundTrip.wearables == [.appleWatch, .garmin])
    }
}
