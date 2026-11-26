import AssistantPresentation
import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing

@MainActor
@Suite("Importing a plan with blocks")
struct PlanImportBlocksTests {
    private let squat = Exercise(name: "Squat (Barbell)", primaryMuscles: [.quadriceps], equipment: .barbell)
    private let now = Date(timeIntervalSince1970: 1_795_089_600)  // 19 November 2026
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private let plan = """
        {"format": "overreach.plan", "version": 1, "startDate": "2027-01-04",
         "routines": [{"id": "lower", "name": "Lower", "exercises": ["Squat (Barbell)"],
                       "prescriptions": [{"exercise": "Squat (Barbell)",
                                          "scheme": {"type": "linearLoad", "sets": 5, "reps": 5}}]}],
         "blocks": [{"name": "Strength", "focus": "strength", "weeks": 6, "routines": ["lower"]},
                    {"focus": "hypertrophy", "weeks": 4, "routines": ["lower"]}]}
        """

    private func model(_ store: TestStore, profiles: Bool = true) -> PlanImportModel {
        let fixedNow = now
        return PlanImportModel(
            exercises: store, routines: store, progression: store, profiles: profiles ? store : nil,
            clock: { fixedNow }, calendar: calendar, format: Format(locale: Locale(identifier: "en_US"))
        )
    }

    @Test func previewsAndSavesTheBlocks() async throws {
        let store = TestStore(exercises: [squat])
        var profile = AthleteProfile()
        let september = CalendarDay(year: 2026, month: 9, day: 1)
        let earlier = TrainingBlock(focus: .hypertrophy, start: september, isDeclared: true)
        profile.declaredBlocks = [earlier]
        try await store.save(profile)
        let model = model(store)

        await model.read(text: plan)
        let preview = try #require(model.preview)
        #expect(preview.canImport)
        #expect(preview.blocks.map(\.name) == ["Strength", "Hypertrophy"])
        #expect(preview.blocks[0].detail == "Strength · 6 weeks from Jan 4, 2027 · 1 session per week · Lower")
        #expect(preview.blocks[1].detail == "4 weeks from Feb 15, 2027 · 1 session per week · Lower")

        #expect(await model.confirm())
        #expect(model.resultMessage == "Imported 1 routines, 0 exercise settings and a plan of 2 blocks.")
        let saved = try await store.profile().declaredBlocks
        #expect(saved.count == 3)
        #expect(saved.first == earlier)
        let routine = try #require(try await store.allRoutines().first)
        #expect(saved[1].routineIDs == [routine.id])
        #expect(routine.prescription(for: squat.id) == .linearLoad(sets: 5, reps: 5, targetRPE: 8))
    }

    @Test func blocksNeedSomewhereToBeSaved() async {
        let model = model(TestStore(exercises: [squat]), profiles: false)
        await model.read(text: plan)
        #expect(model.preview?.canImport == false)
        #expect(await model.confirm() == false)
    }
}
