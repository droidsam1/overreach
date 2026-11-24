import Domain
import Foundation

/// Learns local weekdays for a dog run from explicitly answered, completed runs.
public struct RunCompanionSlots: Sendable {
    public static let lookbackDays = 28
    public static let evidence = EvidenceReference(key: "dog-run-slots", level: .heuristic)

    private let weekdaysWithDog: Set<Int>
    private let weekdaysWithoutDog: Set<Int>

    public init(answers: [(day: CalendarDay, withDog: Bool)], calendar: Calendar) {
        let days = Dictionary(grouping: answers, by: \.day)
        var withDog: [Int: Int] = [:]
        var withoutDog: [Int: Int] = [:]
        for (day, answers) in days {
            let choices = Set(answers.map(\.withDog))
            guard choices.count == 1, let choice = choices.first else { continue }
            let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
            if choice { withDog[weekday, default: 0] += 1 } else { withoutDog[weekday, default: 0] += 1 }
        }
        let minimumConfirmations = 3
        weekdaysWithDog = Set(withDog.keys.filter {
            withDog[$0, default: 0] >= minimumConfirmations && withDog[$0, default: 0] > withoutDog[$0, default: 0]
        })
        weekdaysWithoutDog = Set(withoutDog.keys.filter {
            withoutDog[$0, default: 0] >= minimumConfirmations && withoutDog[$0, default: 0] > withDog[$0, default: 0]
        })
    }

    public var hasLearnedSlots: Bool { !weekdaysWithDog.isEmpty || !weekdaysWithoutDog.isEmpty }

    public func prefersDog(on day: CalendarDay, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day.startDate(in: calendar))
        return weekdaysWithDog.contains(weekday)
    }
}
