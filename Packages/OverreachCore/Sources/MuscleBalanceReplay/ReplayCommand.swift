import Analytics
import Domain
import Foundation

@main
enum ReplayCommand {
    static func main() {
        let paths = Array(CommandLine.arguments.dropFirst())
        if paths.isEmpty || paths == ["--help"] {
            print("Usage: muscle-balance-replay BACKUP.json [BACKUP.json ...]")
            print("Pass one Overreach backup per consenting participant.")
            exit(paths.isEmpty ? 2 : 0)
        }

        var counts = ReplayCounts()
        for (index, path) in paths.enumerated() {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let backup = try BackupCodec.decode(data)
                counts.add(backup)
            } catch {
                let message = "Could not read input backup #\(index + 1). Check the file and backup format.\n"
                FileHandle.standardError.write(Data(message.utf8))
                exit(1)
            }
        }
        counts.printSummary()
    }
}

private struct ReplayCounts {
    typealias Rule = MuscleBalanceFinding.Rule

    private var participants = 0
    private var weeks = 0
    private var participantHits: [Rule: Int] = [:]
    private var weeklyHits: [Rule: Int] = [:]

    mutating func add(_ backup: BackupDocument) {
        let exercises = Dictionary(
            (ExerciseCatalog.builtIn + backup.exercises).map { ($0.id, $0) },
            uniquingKeysWith: { _, saved in saved }
        )
        let calendar = Self.utcCalendar
        let sessions = backup.sessions.filter { session in
            session.isCompleted(through: backup.createdAt)
                && session.entries.contains { $0.sets.contains(where: \.isWorking) }
        }
        guard let oldest = sessions.map(\.startedAt).min(),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: oldest) else { return }

        var participantRules: Set<Rule> = []
        var participantWeeks = 0
        var weekEnd = firstWeek.end
        while weekEnd <= backup.createdAt {
            let assessmentTime = weekEnd.addingTimeInterval(-0.001)
            if let input = MuscleBalance.history(
                sessions: sessions, exercises: exercises, now: assessmentTime, calendar: calendar
            ) {
                participantWeeks += 1
                let findings = MuscleBalance.findings(
                    input: input, goal: backup.profile.goal?.kind ?? .general,
                    block: FocusBalance.activeDeclaredBlock(in: backup.profile, now: assessmentTime, calendar: calendar)
                )
                let rules = Set(findings.map(\.rule))
                participantRules.formUnion(rules)
                for rule in rules {
                    weeklyHits[rule, default: 0] += 1
                }
            }
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekEnd) else { break }
            weekEnd = nextWeek
        }

        guard participantWeeks > 0 else { return }
        participants += 1
        weeks += participantWeeks
        for rule in participantRules {
            participantHits[rule, default: 0] += 1
        }
    }

    func printSummary() {
        print("rule,participants_flagged,participants_assessed,weeks_flagged,weeks_assessed")
        for rule in Rule.allCases {
            let people = participantHits[rule, default: 0]
            let windows = weeklyHits[rule, default: 0]
            print("\(rule.rawValue),\(people),\(participants),\(windows),\(weeks)")
        }
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
