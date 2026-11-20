import Domain
import Foundation
import Testing

@Suite("Strength activity matching")
struct StrengthActivityMatchingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!  // swiftlint:disable:this force_unwrapping
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!  // swiftlint:disable:this force_unwrapping
    }

    private func session(_ start: Date, minutes: Double?) -> StrengthSession {
        StrengthSession(name: "Upper", startedAt: start, endedAt: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    private func watch(_ id: String, _ start: Date, minutes: Double) -> RecordedStrengthActivity {
        RecordedStrengthActivity(
            id: id, source: .garmin, startedAt: start, durationSeconds: minutes * 60,
            averageHeartRate: 112, trainingLoad: 48
        )
    }

    @Test func theSameWorkoutMatchesEvenWhenTheWatchStartsEarlyAndStopsLate() {
        let logged = session(date(19, 18, 0), minutes: 60)
        let recorded = watch("g1", date(19, 17, 55), minutes: 75)

        let matches = StrengthActivityMatching.match(sessions: [logged], activities: [recorded])

        #expect(matches.activity(for: logged.id) == recorded)
        #expect(matches.unmatched.isEmpty)
    }

    @Test func aWorkoutLaterTheSameDayIsNotTheSameWorkout() {
        let logged = session(date(19, 8, 0), minutes: 50)
        let evening = watch("g1", date(19, 19, 0), minutes: 45)

        let matches = StrengthActivityMatching.match(sessions: [logged], activities: [evening])

        #expect(matches.activity(for: logged.id) == nil)
        #expect(matches.unmatched == [evening])
    }

    @Test func aSmallOverlapIsNotEnough() {
        let logged = session(date(19, 18, 0), minutes: 60)
        let next = watch("g1", date(19, 18, 45), minutes: 60)  // 15 of 60 minutes overlap

        let matches = StrengthActivityMatching.match(sessions: [logged], activities: [next])

        #expect(matches.bySession.isEmpty)
        #expect(matches.unmatched == [next])
    }

    @Test func twoSessionsOnTheSameDayEachGetTheirOwnRecording() {
        let morning = session(date(19, 7, 0), minutes: 45)
        let evening = session(date(19, 19, 0), minutes: 60)
        let morningWatch = watch("g-am", date(19, 7, 2), minutes: 44)
        let eveningWatch = watch("g-pm", date(19, 18, 58), minutes: 63)

        let matches = StrengthActivityMatching.match(
            sessions: [evening, morning], activities: [eveningWatch, morningWatch]
        )

        #expect(matches.activity(for: morning.id)?.id == "g-am")
        #expect(matches.activity(for: evening.id)?.id == "g-pm")
        #expect(matches.unmatched.isEmpty)
    }

    @Test func aRecordingGoesToTheSessionItOverlapsMost() {
        // Two logged sessions back to back (e.g. one split in two) and one watch recording covering mostly the first.
        let first = session(date(19, 18, 0), minutes: 40)
        let second = session(date(19, 18, 40), minutes: 30)
        let recorded = watch("g1", date(19, 18, 0), minutes: 50)

        let matches = StrengthActivityMatching.match(sessions: [second, first], activities: [recorded])

        #expect(matches.activity(for: first.id) == recorded)
        #expect(matches.activity(for: second.id) == nil)
    }

    @Test func aSessionWithoutAnEndMatchesOnStartTime() {
        let open = session(date(19, 18, 0), minutes: nil)
        let close = watch("g1", date(19, 18, 10), minutes: 60)
        let far = watch("g2", date(19, 18, 40), minutes: 60)

        let near = StrengthActivityMatching.match(sessions: [open], activities: [close])
        let tooFar = StrengthActivityMatching.match(sessions: [open], activities: [far])

        #expect(near.activity(for: open.id) == close)
        #expect(tooFar.bySession.isEmpty)
    }

    @Test func anOverlapWinsOverAStartTimeOnlyMatch() {
        let open = session(date(19, 18, 0), minutes: nil)
        let complete = session(date(19, 18, 5), minutes: 55)
        let recorded = watch("g1", date(19, 18, 2), minutes: 60)

        let matches = StrengthActivityMatching.match(sessions: [open, complete], activities: [recorded])

        #expect(matches.activity(for: complete.id) == recorded)
        #expect(matches.activity(for: open.id) == nil)
    }

    @Test func unmatchedRecordingsAreOldestFirstAndInputOrderDoesNotMatter() {
        let logged = session(date(19, 18, 0), minutes: 60)
        let same = watch("g2", date(19, 18, 1), minutes: 59)
        let earlier = watch("g1", date(17, 18, 0), minutes: 60)
        let later = watch("g3", date(20, 18, 0), minutes: 60)

        let forward = StrengthActivityMatching.match(sessions: [logged], activities: [earlier, same, later])
        let backward = StrengthActivityMatching.match(sessions: [logged], activities: [later, same, earlier])

        #expect(forward == backward)
        #expect(forward.activity(for: logged.id) == same)
        #expect(forward.unmatched.map(\.id) == ["g1", "g3"])
    }

    @Test func nothingToMatch() {
        let empty = StrengthActivityMatching.match(sessions: [], activities: [])
        #expect(empty.bySession.isEmpty)
        #expect(empty.unmatched.isEmpty)

        let logged = session(date(19, 18), minutes: 60)
        let onlySessions = StrengthActivityMatching.match(sessions: [logged], activities: [])
        #expect(onlySessions.bySession.isEmpty)
    }
}
