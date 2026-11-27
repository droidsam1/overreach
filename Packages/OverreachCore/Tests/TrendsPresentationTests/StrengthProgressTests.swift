import Analytics
import Domain
import Foundation
import PresentationKit
import Testing
@testable import TrendsPresentation

struct StrengthProgressTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let calendar = Calendar(identifier: .gregorian)
    private let exercise = Exercise(name: "Lateral raise", primaryMuscles: [.sideDelts], equipment: .dumbbell)

    @Test func recordedMetricShowsBothSourcesInChronologicalOrder() throws {
        let imported = workout(.strongImport, daysAgo: 10, loads: [8, 10])
        let local = workout(.app, daysAgo: 3, loads: [10, 12])
        let older = workout(.app, daysAgo: 40, loads: [9])
        let series = try heaviest([local, older, imported])

        let importedSet = try #require(imported.entries.first?.sets.last)
        let localSet = try #require(local.entries.first?.sets.last)
        #expect(series.points.map(\.id) == [
            .strength(sessionID: imported.id, setID: importedSet.id),
            .strength(sessionID: local.id, setID: localSet.id)
        ])
        #expect(series.points.map(\.source) == [.strongImport, .app])
        #expect(series.points.map(\.value) == [10, 12])
        #expect(series.hasMultipleSources)
        #expect(series.best?.source == .app)
        #expect(series.comparison == L10n.format("Sessions this period {1} · Previous period {2}", "2", "1"))
    }

    @Test func medianChangeRequiresTheSameSourceAcrossBothPeriods() throws {
        let recent = workout(.app, daysAgo: 3, loads: [12])
        let olderImport = workout(.strongImport, daysAgo: 40, loads: [9])
        let olderLocal = workout(.app, daysAgo: 40, loads: [9])
        let mixed = try heaviest([recent, olderImport])
        let local = try heaviest([recent, olderLocal])
        let counts = L10n.format("Sessions this period {1} · Previous period {2}", "1", "1")

        #expect(!mixed.hasMultipleSources)
        #expect(mixed.comparison == counts)
        #expect(local.comparison == L10n.format("Median change {1} · {2}", "+3 kg", counts))
    }

    private func heaviest(_ workouts: [StrengthSession]) throws -> PerformanceSeries {
        let window = PerformanceComparison(through: CalendarDay(now, calendar: calendar), days: 30, calendar: calendar)
        let progress = PerformanceProgress(window: window, format: Format(locale: Locale(identifier: "en_US")))
        let sets = StrengthPerformance.recordedSets(in: workouts, through: now)
        let lift = try #require(progress.strengthOptions(sets, exercises: [exercise]).first)
        return try #require(progress.strengthSeries(lift, profile: nil, now: now, calendar: calendar).first)
    }

    private func workout(_ source: DataSourceKind, daysAgo: Int, loads: [Double]) -> StrengthSession {
        let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return StrengthSession(
            name: "Strength session", startedAt: start, endedAt: start.addingTimeInterval(600),
            entries: [ExerciseEntry(exerciseID: exercise.id, sets: loads.map { WorkoutSet(weightKg: $0, reps: 8) })],
            source: source
        )
    }
}
