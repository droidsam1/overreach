import PresentationKit
import Testing

@Suite("Section availability")
struct SectionAvailabilityTests {
    @Test func recoveryNeedsOneReading() {
        #expect(!SectionAvailability.recovery(readings: 0))
        #expect(SectionAvailability.recovery(readings: 1))
        #expect(SectionAvailability.recovery(readings: 30))
    }

    @Test func recentLoadNeedsARowAndHistoryASessionOrARun() {
        #expect(!SectionAvailability.recentLoad(rows: 0))
        #expect(SectionAvailability.recentLoad(rows: 2))
        #expect(SectionAvailability.history(sessions: 1, runs: 0))
        #expect(SectionAvailability.history(sessions: 0, runs: 1))
        #expect(SectionAvailability.history(sessions: 12, runs: 3))
        #expect(!SectionAvailability.history(sessions: 0, runs: 0))
    }

    @Test func progressNeedsAGoalOrALiftTrainedTwice() {
        #expect(!SectionAvailability.progress(hasGoal: false, sessionsOfMostTrainedLift: 0))
        #expect(!SectionAvailability.progress(hasGoal: false, sessionsOfMostTrainedLift: 1))
        #expect(SectionAvailability.progress(hasGoal: false, sessionsOfMostTrainedLift: 2))
        #expect(SectionAvailability.progress(hasGoal: true, sessionsOfMostTrainedLift: 0))
    }

    @Test func aChartNeedsPoints() {
        #expect(!SectionAvailability.charts(withData: 0))
        #expect(SectionAvailability.charts(withData: 2))
    }

    @Test func theHintAppearsOnlyWhenNothingIsAvailable() {
        #expect(SectionAvailability.unlockHint(recovery: false, recentLoad: false, progress: false) != nil)
        #expect(SectionAvailability.unlockHint(recovery: true, recentLoad: false, progress: false) == nil)
        #expect(SectionAvailability.unlockHint(recovery: false, recentLoad: false, progress: true) == nil)
    }
}
