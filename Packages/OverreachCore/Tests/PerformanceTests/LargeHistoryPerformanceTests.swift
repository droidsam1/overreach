import Analytics
import Domain
import Fixtures
import Foundation
@testable import StrongImport
import Testing

/// Time budgets for a real-sized history (~600 sessions, ~15k sets). Budgets are generous for debug builds on
/// CI runners; they catch accidental quadratic work, not small regressions.
@Suite("Large history performance", .serialized)
struct LargeHistoryPerformanceTests {
    private static let history = LargeHistory()
    private var history: LargeHistory { Self.history }
    private var now: Date { history.sessions.last?.startedAt.addingTimeInterval(86_400) ?? Date() }

    private func measure(_ label: String, _ work: () -> Void) -> Duration {
        let elapsed = ContinuousClock().measure(work)
        print("⏱ \(label): \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], fractionalPart: .show(length: 0))))")
        return elapsed
    }

    @Test func fixtureHasTheSizeOfARealExport() {
        #expect(history.sessions.count == 600)
        #expect(history.setCount >= 12_000)
    }

    @Test func parsesTheStrongCSVQuickly() throws {
        var result: StrongCSVImporter.Result?
        let elapsed = measure("parse CSV") {
            result = try? StrongCSVImporter.parse(
                history.csv, catalog: ExerciseCatalog.builtIn, options: .init(calendar: LargeHistory.calendar)
            )
        }
        let parsed = try #require(result)
        #expect(parsed.sessions.count == history.sessions.count)
        #expect(parsed.setCount == history.setCount)
        #expect(parsed.newExercises.count == 3)
        #expect(parsed.skippedLines.isEmpty)
        #expect(elapsed < .seconds(5))
    }

    @Test func infersBlocksQuickly() {
        var blocks: [TrainingBlock] = []
        let elapsed = measure("infer blocks") {
            blocks = BlockAdvisor.inferBlocks(sessions: history.sessions, calendar: LargeHistory.calendar)
        }
        #expect(!blocks.isEmpty)
        #expect(elapsed < .seconds(2))
    }

    @Test func findsBalanceIssuesQuickly() {
        let exercises = Dictionary(history.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var profile = AthleteProfile()
        let trained = history.sessions.prefix(4).flatMap { $0.entries.map(\.exerciseID) }
        profile.goal = TrainingGoal(kind: .strength, priorityLifts: Array(trained.prefix(8)))
        let settings = Dictionary(
            trained.compactMap { exercises[$0] }.map { exercise in
                var config = ProgressionSettings(for: exercise)
                config.focus = .strength
                return (exercise.id, config)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let elapsed = measure("balance findings") {
            _ = FocusBalance.findings(
                sessions: history.sessions, exercises: exercises, exerciseSettings: settings, profile: profile, now: now
            )
        }
        #expect(elapsed < .seconds(2))
    }

    @Test func analysesThePlanQuickly() {
        let exercises = Dictionary(history.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var analysis: PlanAnalysis?
        let elapsed = measure("plan analysis (full history)") {
            analysis = PlanAnalysis.run(
                profile: AthleteProfile(), sessions: history.sessions, exercises: exercises, settings: [:],
                now: now, calendar: LargeHistory.calendar
            )
        }
        #expect(analysis?.currentBlock != nil)
        #expect(elapsed < .seconds(2))
    }
}

@Suite("Exposure index")
struct ExposureIndexTests {
    private static let history = LargeHistory(sessionCount: 120, seed: 7)

    @Test func matchesPerExerciseHistory() {
        let sessions = Self.history.sessions.shuffled()
        let index = ExposureIndex(sessions: sessions)
        let ids = Set(sessions.flatMap { $0.entries.map(\.exerciseID) })
        for id in ids {
            #expect(index.exposures(of: id) == ExerciseExposure.history(of: id, in: sessions))
        }
    }

    @Test func classifiesSessionsLikeTheUnindexedVersion() {
        let sessions = Self.history.sessions
        let index = ExposureIndex(sessions: sessions)
        for session in sessions {
            let previous = sessions.filter { $0.startedAt < session.startedAt }
            var foci: [TrainingFocus] = []
            for entry in session.entries {
                let history = ExerciseExposure.history(of: entry.exerciseID, in: previous)
                let current = ExerciseExposure(date: session.startedAt, sets: entry.sets)
                let reference = (history.suffix(6) + [current]).compactMap(\.bestEstimatedOneRepMax).max()
                foci += current.sets.compactMap { FocusClassifier.focus(of: $0, oneRepMaxKg: reference) }
            }
            #expect(FocusClassifier.focus(of: session, index: index) == FocusClassifier.dominant(foci))
        }
    }

    @Test func exposuresBeforeADateExcludeThatDate() throws {
        let index = ExposureIndex(sessions: Self.history.sessions)
        let exerciseID = try #require(Self.history.sessions.first?.entries.first?.exerciseID)
        let all = index.exposures(of: exerciseID)
        let pivot = all[all.count / 2].date
        let before = index.exposures(of: exerciseID, before: pivot)
        #expect(before.count == all.count / 2)
        #expect(before.allSatisfy { $0.date < pivot })
    }
}
