import Domain
import Fixtures
import Foundation
import PresentationKit
import Testing
import TodayPresentation

/// The readiness explanation orders workouts and races by the sleep behind each HRV reading (ADR-0034).
@MainActor
@Suite("Readiness timing and races")
struct ReadinessTimingTests {
    private let today = CalendarDay(year: 2026, month: 11, day: 20)

    private func madrid() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        return calendar
    }

    /// Thirty nights of Garmin RMSSD: four recent low nights, three unmeasured, a stable baseline before them.
    /// Each night runs from 23:00 to 07:00 and belongs to the day it ends.
    private func nights(_ calendar: Calendar, edit: (Int, inout DailyMetrics) -> Void = { _, _ in }) -> [DailyMetrics] {
        (0...30).map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            var metrics = DailyMetrics(day: day, sources: [.garmin])
            metrics.hrvRMSSDMs = switch offset {
            case 0...3: 32
            case 4...6: nil
            default: 50
            }
            metrics.sleepSeconds = 8 * 3_600
            metrics.sleepStart = day.startDate(in: calendar).addingTimeInterval(-3_600)
            metrics.sleepEnd = day.startDate(in: calendar).addingTimeInterval(7 * 3_600)
            edit(offset, &metrics)
            return metrics
        }
    }

    private func at(_ offset: Int, hour: Double, _ calendar: Calendar) -> Date {
        today.adding(days: offset, calendar: calendar).startDate(in: calendar).addingTimeInterval(hour * 3_600)
    }

    private func run(_ id: String, name: String, at start: Date, minutes: Double = 40) -> RunActivity {
        RunActivity(id: id, source: .garmin, name: name, startedAt: start, durationSeconds: minutes * 60,
                    distanceMeters: 8_000)
    }

    private func model(
        _ calendar: Calendar, nights: [DailyMetrics], runs: [RunActivity], races: [RunActivity] = []
    ) async throws -> TodayModel {
        let store = TestStore()
        if let race = races.first {
            let planned = PlannedRun(day: CalendarDay(race.startedAt, calendar: calendar), purpose: .race,
                                     distanceMeters: 10_000, completion: PlannedRunCompletion(race))
            try await store.save(AthleteProfile(goal: TrainingGoal(
                kind: .hybrid, running: RunningGoal(distanceMeters: 10_000), nextRun: planned
            )))
        }
        return TodayModel(sources: [NightSource(days: nights, activities: runs)], profiles: store, calendar: calendar,
                          format: Format(locale: Locale(identifier: "en_US")))
    }

    @Test func anOvernightWorkoutBeforeTheReadingsSleepCountsAndALaterOneDoesNot() async throws {
        let calendar = try madrid()
        // Last night started at 01:30 today, after a run that ended past midnight.
        let data = nights(calendar) { offset, night in
            if offset == 0 { night.sleepStart = at(0, hour: 1.5, calendar) }
        }
        let overnight = run("overnight", name: "Late run", at: at(-1, hour: 23.9, calendar))
        let beforeWaking = run("early", name: "Before the previous wake", at: at(-1, hour: 5, calendar))
        let afterReading = run("after", name: "This morning", at: at(0, hour: 9, calendar))
        let model = try await model(calendar, nights: data, runs: [overnight, beforeWaking, afterReading])

        await model.load(now: at(0, hour: 14, calendar))

        #expect(model.readinessLevel == .amber)
        let context = try #require(model.readinessTrainingContext)
        #expect(context.heading.hasPrefix("Workouts since your last sleep, before the night of your latest comparable"))
        #expect(context.workouts.count == 1)
        #expect(context.workouts.first?.contains("Late run") == true)
    }

    @Test func withoutThePreviousNightTheWindowIsTheDayBeforeTheSleep() async throws {
        let calendar = try madrid()
        let data = nights(calendar) { offset, night in
            if offset == 1 { night.sleepStart = nil }
        }
        let evening = run("evening", name: "Intervals", at: at(-1, hour: 19, calendar))
        let model = try await model(calendar, nights: data, runs: [evening])

        await model.load(now: at(0, hour: 14, calendar))

        let context = try #require(model.readinessTrainingContext)
        #expect(context.heading.hasPrefix("Workouts in the 24 hours before the night of your latest comparable"))
        #expect(context.workouts.first?.contains("Intervals") == true)
    }

    @Test func aRaceBeforeTheDipShowsTheReadingsAroundIt() async throws {
        let calendar = try madrid()
        let race = run("race", name: "City 10K", at: at(-4, hour: 9, calendar))
        let model = try await model(calendar, nights: nights(calendar), runs: [race], races: [race])

        await model.load(now: at(0, hour: 14, calendar))

        let comparison = try #require(model.readinessContext.last)
        #expect(comparison.hasPrefix("Confirmed race on "))
        #expect(comparison.contains("Comparable HRV (RMSSD) before it: 50 ms on "))
        #expect(comparison.contains("After it: 32 ms on "))
        let tagged = model.recentTrainingDays.flatMap(\.workouts).filter { $0.contains("Race: City 10K") }
        #expect(tagged.count == 1)
    }

    @Test func aDipBeforeARaceHasNoReadingAfterItYet() async throws {
        let calendar = try madrid()
        let race = run("race", name: "Parkrun", at: at(0, hour: 9, calendar), minutes: 20)
        let model = try await model(calendar, nights: nights(calendar), runs: [race], races: [race])

        await model.load(now: at(0, hour: 14, calendar))

        let comparison = try #require(model.readinessContext.last)
        #expect(comparison.contains("before it: 32 ms on "))
        #expect(comparison.hasSuffix("No comparable reading after it yet."))
    }

    @Test func aRunNamedLikeARaceIsNotARaceWithoutTheAthletesLink() async throws {
        let calendar = try madrid()
        let named = run("named", name: "Race pace 10K", at: at(-4, hour: 9, calendar))
        let model = try await model(calendar, nights: nights(calendar), runs: [named])

        await model.load(now: at(0, hour: 14, calendar))

        #expect(model.readinessContext.contains { $0.hasPrefix("Confirmed race") } == false)
        #expect(model.recentTrainingDays.flatMap(\.workouts).contains { $0.contains("Race: ") } == false)
    }

    @Test func emptyTrainingHistoryAddsNoTrainingContext() async throws {
        let calendar = try madrid()
        let model = try await model(calendar, nights: nights(calendar), runs: [])

        await model.load(now: at(0, hour: 14, calendar))

        #expect(model.readinessLevel == .amber)
        #expect(model.readinessTrainingContext == nil)
        #expect(model.readinessContext.contains { $0.hasPrefix("Confirmed race") } == false)
    }
}

private struct NightSource: MetricsSource {
    let kind = DataSourceKind.garmin
    let days: [DailyMetrics]
    let activities: [RunActivity]

    func isAvailable() async -> Bool { true }
    func requestAccess() async {}
    func dailyMetrics(in range: ClosedRange<CalendarDay>) async throws -> [DailyMetrics] {
        days.filter { range.contains($0.day) }
    }
    func runs(from start: Date, to end: Date) async throws -> [RunActivity] {
        activities.filter { (start...end).contains($0.startedAt) }
    }
}
