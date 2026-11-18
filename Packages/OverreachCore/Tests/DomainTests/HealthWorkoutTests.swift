import Domain
import Foundation
import Testing

@Suite("Sessions in Apple Health")
struct HealthWorkoutTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func onlyTimedSessionsLoggedInTheAppBelongThere() {
        let end = start.addingTimeInterval(3_600)
        #expect(StrengthSession(name: "A", startedAt: start, endedAt: end).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start, endedAt: start).belongsInHealth)
        #expect(!StrengthSession(name: "A", startedAt: start, endedAt: end, source: .strongImport).belongsInHealth)
    }
}
